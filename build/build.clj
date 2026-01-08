(ns build
  (:require
   [clojure.string :as str]
   [clojure.tools.build.api :as b]
   [k16.kaven.deploy :as kaven.deploy]))

(def basis (delay (b/create-basis {})))

(def lib 'io.julienvincent/clojure-test)
(def version (str/replace (or (System/getenv "VERSION") "0.0.0") #"v" ""))
(def class-dir "target/classes")
(def jar-file "target/lib.jar")

(defn clean [_]
  (b/delete {:path "target"}))

(defn build [_]
  (clean nil)

  (b/write-pom {:class-dir class-dir
                :lib lib
                :version version
                :basis @basis
                :src-dirs ["clojure"]
                :pom-data [[:description "Clojure test integration for neovim"]
                           [:url "https://github.com/julienvincent/clojure-test.nvim"]
                           [:licenses
                            [:license
                             [:name "MIT"]
                             [:url "https://opensource.org/license/mit"]]]]})

  (b/copy-dir {:src-dirs ["clojure/src"]
               :target-dir class-dir})

  (b/jar {:class-dir class-dir
          :jar-file jar-file}))

(def ^:private clojars-credentials
  {:username (System/getenv "CLOJARS_USERNAME")
   :password (System/getenv "CLOJARS_PASSWORD")})

(defn release [_]
  (kaven.deploy/deploy
   {:jar-path (b/resolve-path jar-file)
    :repository {:id "clojars"
                 :credentials clojars-credentials}}))

