(ns io.julienvincent.clojure-test.test.example)

(defn throws-inner []
  (throw (ex-info "Bad" {:data 1})))

(defn throws []
  (try (throws-inner)
       (catch Exception ex
         (throw (ex-info "Wrapped" {:data 2} ex)))))
