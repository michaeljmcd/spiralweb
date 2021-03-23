(ns spiralweb.core-test
 (:require [clojure.test :refer :all]
           [spiralweb.core :refer :all]
           [edessa.parser :refer [success? failure? apply-parser result]]
           [taoensso.timbre :as t :refer [debug error]]))

(deftest tangle-tests
 (let [circular-text "@code a\n@<b>\n@end\n@code b\n@<a>\n@end"
       result (tangle-text circular-text [])]
    (is (= nil result))))
