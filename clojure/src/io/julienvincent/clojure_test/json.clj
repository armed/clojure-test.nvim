(ns io.julienvincent.clojure-test.json
  (:require
   [io.julienvincent.clojure-test.query :as api.query]
   [io.julienvincent.clojure-test.runner :as api.runner]
   [io.julienvincent.clojure-test.serialization :as api.serialization]
   [jsonista.core :as json]))

(def ^:private json-mapper
  (json/object-mapper))

(defn- error-code [ex]
  (or (some-> ex ex-data :code name)
      (some-> ex ex-data :type name)
      "rpc-error"))

(defn- error-payload [ex]
  {:ok false
   :error {:code (error-code ex)
           :message (or (.getMessage ex) "Unknown RPC error")
           :details (some-> ex ex-data pr-str)}})

(defmacro ^:private with-json-envelope [& body]
  `(try
     (json/write-value-as-string {:ok true :data (do ~@body)} json-mapper)
     (catch Throwable ex#
       (json/write-value-as-string (error-payload ex#) json-mapper))))

#_{:clj-kondo/ignore [:clojure-lsp/unused-public-var]}
(defn ^:deprecated get-test-namespaces []
  (with-json-envelope
    (api.query/get-test-namespaces)))

#_{:clj-kondo/ignore [:clojure-lsp/unused-public-var]}
(defn ^:deprecated get-tests-in-ns [namespace]
  (with-json-envelope
    (api.query/get-tests-in-ns namespace)))

#_{:clj-kondo/ignore [:clojure-lsp/unused-public-var]}
(defn get-all-tests []
  (with-json-envelope
    (api.query/get-all-tests)))

#_{:clj-kondo/ignore [:clojure-lsp/unused-public-var]}
(defn load-test-namespaces []
  (with-json-envelope
    (doseq [namespace (api.query/get-test-namespaces)]
      (when-not (find-ns namespace)
        (require namespace)))))

#_{:clj-kondo/ignore [:clojure-lsp/unused-public-var]}
(defn run-test [test-sym]
  (with-json-envelope
    (api.runner/run-test test-sym)))

#_{:clj-kondo/ignore [:clojure-lsp/unused-public-var]}
(defn resolve-metadata-for-symbol [sym]
  (with-json-envelope
    (api.query/resolve-metadata-for-symbol sym)))

#_{:clj-kondo/ignore [:clojure-lsp/unused-public-var]}
(defn analyze-exception [sym]
  (with-json-envelope
    (if-let [resolved (resolve sym)]
      (api.serialization/analyze-exception (var-get resolved))
      (throw (ex-info (str "Unable to resolve symbol: " sym)
                      {:code :symbol-not-found
                       :symbol (str sym)})))))

#_{:clj-kondo/ignore [:clojure-lsp/unused-public-var]}
(defn get-tests-in-path [path]
  (with-json-envelope
    (api.query/get-tests-in-path path)))

#_{:clj-kondo/ignore [:clojure-lsp/unused-public-var]}
(defn run-tests-parallel-start [test-syms opts]
  (with-json-envelope
    (api.runner/run-tests-parallel-start test-syms opts)))

#_{:clj-kondo/ignore [:clojure-lsp/unused-public-var]}
(defn stop-parallel-tests []
  (with-json-envelope
    (api.runner/stop-parallel-tests)))

#_{:clj-kondo/ignore [:clojure-lsp/unused-public-var]}
(defn get-parallel-results []
  (with-json-envelope
    (api.runner/get-parallel-results)))
