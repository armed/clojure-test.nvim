(ns clojure-test.fixture-test
  (:require
   [clojure-test.fixture :as fixture]
   [clojure.test :refer [deftest is]]))

(deftest foo-test
  (is (= "bar" (fixture/foo))))

(deftest ^:integration with-metadata-test
  (is (= "bar" (fixture/foo))))
