(ns io.julienvincent.clojure-test.runner
  (:require
   [clojure.test :as test]
   [eftest.runner :as eftest]
   [io.julienvincent.clojure-test.serialization :as serialization]))

(def ^:dynamic ^:private *report* nil)

(defn- parse-report [report]
  (let [exceptions (when (instance? Throwable (:actual report))
                     (serialization/analyze-exception (:actual report)))

        report (cond-> (select-keys report [:type])
                 (:expected report)
                 (assoc :expected (serialization/parse-diff (:expected report)))

                 (and (:actual report)
                      (not exceptions))
                 (assoc :actual (serialization/parse-diff (:actual report)))

                 exceptions (assoc :exceptions exceptions))]

    (assoc report :context test/*testing-contexts*)))

(defn run-test [test-sym]
  (binding [*report* (atom [])]
    (with-redefs [test/report (fn [report]
                                (swap! *report*
                                       conj
                                       (parse-report report)))]
      (try (test/run-test-var (resolve test-sym))
           (catch Exception ex
             (swap! *report* conj {:type :error
                                   :exceptions (serialization/analyze-exception ex)}))))
    @*report*))

(defonce ^:private parallel-results (atom {}))
(defonce ^:private parallel-running (atom false))
(defonce ^:private stop-requested (atom false))

(defn- capturing-reporter [event]
  (when @stop-requested
    (throw (ex-info "Test run cancelled" {:type :cancelled})))

  (let [test-var (first test/*testing-vars*)
        test-sym (when test-var
                   (symbol (-> test-var meta :ns ns-name str)
                           (-> test-var meta :name str)))]
    (when (and test-sym (#{:pass :fail :error} (:type event)))
      (swap! parallel-results
             update (str test-sym)
             (fn [current]
               (-> (or current {:test (str test-sym) :status "running" :assertions []})
                   (update :assertions conj (parse-report event))
                   (assoc :status (if (#{:fail :error} (:type event)) "failed" "passed"))))))))

(defn run-tests-parallel-start [test-syms opts]
  (reset! parallel-results {})
  (reset! parallel-running true)
  (reset! stop-requested false)

  (doseq [sym test-syms]
    (swap! parallel-results assoc (str sym) {:test (str sym) :status "pending" :assertions []}))

  (future
    (try
      (let [test-vars (keep resolve test-syms)]
        (eftest/run-tests
         test-vars
         (merge
          {:report capturing-reporter
           :capture-output? false}
          (select-keys opts [:thread-count :multithread?]))))
      (catch clojure.lang.ExceptionInfo e
        (when-not (= :cancelled (:type (ex-data e)))
          (throw e)))
      (finally
        (reset! parallel-running false))))

  {:started true :count (count test-syms)})

(defn stop-parallel-tests []
  (reset! stop-requested true)
  {:stopped true})

(defn get-parallel-results []
  {:running @parallel-running
   :results @parallel-results})
