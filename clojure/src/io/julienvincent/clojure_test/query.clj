(ns io.julienvincent.clojure-test.query
  (:require
   [clojure.java.io :as io]
   [clojure.string :as str])
  (:import
   java.io.File
   java.net.URI
   java.nio.file.Paths))

(defn- is-parent [parent child]
  (let [parent (-> (Paths/get (URI. (str "file://" parent)))
                   .toAbsolutePath
                   .normalize)
        child (-> (Paths/get (URI. (str "file://" child)))
                  .toAbsolutePath
                  .normalize)]

    (.startsWith child parent)))

(defn- remove-overlapping-directories
  "Remove overlapping paths from a given collection of directories, keeping the
   more specific path.

   Example:

   ```clj
   (remove-overlapping-directories #{\"/a\" \"/a/b\" \"/c\"})
   ;; =>
   #{\"/a/b\" \"/c\" }
   ```"
  [classpath]
  (->> classpath
       (sort-by identity (fn [left right]
                           (compare (count left) (count right))))
       (reduce
        (fn [paths path]
          (let [paths (filterv
                       (fn [existing]
                         (not (is-parent existing path)))
                       paths)]
            (conj paths path)))
        [])))

(defn- get-classpath []
  (remove-overlapping-directories
   (into #{}
         (comp
          (filter (fn [path]
                    (let [file ((requiring-resolve 'clojure.java.io/file) path)]
                      (and (.exists file)
                           (.isDirectory file)))))
          (map (fn [path]
                 (->> (File. path)
                      .getAbsolutePath
                      str)))
          (filter (fn [path]
                    (is-parent (System/getProperty "user.dir") path))))
         (str/split (System/getProperty "java.class.path") #":"))))

(defn- find-test-files []
  (mapcat
   (fn [dir]
     (into []
           (comp
            (filter (fn [file]
                      (.isFile file)))
            (map (fn [file]
                   (subs (.getAbsolutePath file) (inc (count dir)))))

            (filter (fn [path]
                      (re-find #"_test.clj" path))))
           (file-seq (io/file dir))))
   (get-classpath)))

(defn get-test-namespaces []
  (let [test-files (find-test-files)]
    (mapv
     (fn [file]
       (let [without-ext (str/replace file #"\.clj" "")
             as-ns (-> without-ext
                       (str/replace #"/" ".")
                       (str/replace #"_" "-"))]
         (symbol as-ns)))
     test-files)))

(defn get-tests-in-ns [namespace]
  (when-not (find-ns namespace)
    (require namespace))
  (into []
        (comp
         (filter
          (fn [[_ var]]
            (:test (meta var))))
         (map (fn [[sym]]
                (symbol (str namespace) (str sym)))))
        (ns-interns namespace)))

(defn get-all-tests []
  (mapcat get-tests-in-ns (get-test-namespaces)))

(defn- file-to-namespace [file-path]
  (-> file-path
      (str/replace #"\.clj$" "")
      (str/replace #"/" ".")
      (str/replace #"_" "-")
      symbol))

(defn get-tests-in-path [search-path]
  (let [project-root (System/getProperty "user.dir")
        normalized-search (str/replace search-path #"/$" "")
        ^java.io.File target (io/file project-root normalized-search)]

    (cond
      (and (.exists target) (.isFile target))
      (when (re-find #"_test\.clj$" (.getName target))
        (let [abs-path (.getAbsolutePath target)]
          (when-let [relative-path
                     (some
                      (fn [classpath-dir]
                        (when (is-parent classpath-dir abs-path)
                          (subs abs-path (inc (count classpath-dir)))))
                      (get-classpath))]
            (get-tests-in-ns (file-to-namespace relative-path)))))

      (and (.exists target) (.isDirectory target))
      (let [files (file-seq target)]
        (->> files
             (filter (fn [^java.io.File file]
                       (and (.isFile file)
                            (re-find #"_test\.clj$" (.getName file)))))
             (keep (fn [^java.io.File file]
                     (let [abs-path (.getAbsolutePath file)]
                       (some
                        (fn [classpath-dir]
                          (when (is-parent classpath-dir abs-path)
                            (subs abs-path (inc (count classpath-dir)))))
                        (get-classpath)))))
             (map file-to-namespace)
             (mapcat get-tests-in-ns)))

      :else
      [])))

(defn- namespace-to-file [sym]
  (-> (str sym)
      (str/replace #"\." "/")
      (str/replace #"-" "_")
      (str ".clj")))

(defn resolve-metadata-for-symbol [sym]
  (let [meta-info (if (qualified-symbol? sym)
                    (meta (requiring-resolve sym))
                    {:file (namespace-to-file sym)})
        file-path (:file meta-info)

        absolute-path
        (if (-> file-path (File.) .isAbsolute)
          file-path
          (some
           (fn [classpath-dir]
             (let [file (File. classpath-dir file-path)]
               (when (.exists file)
                 (.getAbsolutePath file))))
           (get-classpath)))]

    (when absolute-path
      (-> (select-keys meta-info [:line :column])
          (assoc :file absolute-path)))))
