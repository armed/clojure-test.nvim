(ns io.julienvincent.clojure-test.serialization-test
  (:require
   [io.julienvincent.clojure-test.test.example :as test.example]
   [matcher-combinators.test]
   [matcher-combinators.matchers :as m]
   [io.julienvincent.clojure-test.serialization :as serialization]
   [clojure.test :refer [deftest is]]))

(deftest analyze-exception-test
  (try
    (test.example/throws)
    (is false "Should never reach here")
    (catch Exception ex
      (is (match? [{:class-name "clojure.lang.ExceptionInfo"
                    :message "Wrapped"
                    :properties "{:data 2}\n"
                    :stack-trace []}
                   {:class-name "clojure.lang.ExceptionInfo"
                    :message "Bad"
                    :properties "{:data 1}\n"
                    :stack-trace
                    (m/prefix [{:simple-class string?
                                :package "io.julienvincent.clojure_test.test"
                                :is-clojure? true
                                :method "invokeStatic"
                                :name "io.julienvincent.clojure-test.test.example/throws-inner"
                                :file "example.clj"
                                :line 4
                                :id "io.julienvincent.clojure-test.test.example/throws-inner:4"
                                :class "io.julienvincent.clojure_test.test.example$throws_inner"
                                :location {:file #".*clojure/test/io/julienvincent/clojure_test/test/example.clj"}
                                :names ["io.julienvincent.clojure-test.test.example"
                                        "throws-inner"]}
                               {:package "io.julienvincent.clojure_test.test"
                                :is-clojure? true
                                :method "invokeStatic"
                                :name "io.julienvincent.clojure-test.test.example/throws"
                                :file "example.clj"
                                :line 7
                                :id "io.julienvincent.clojure-test.test.example/throws:7"
                                :class "io.julienvincent.clojure_test.test.example$throws"
                                :location
                                {:file #".*/clojure/test/io/julienvincent/clojure_test/test/example.clj"}
                                :names
                                ["io.julienvincent.clojure-test.test.example"
                                 "throws"]}])}]
                  (serialization/analyze-exception ex))))))
