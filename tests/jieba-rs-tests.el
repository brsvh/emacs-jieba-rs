;;; jieba-rs-tests.el --- Integration tests for jieba-rs  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Bingshan Chang <chang@bingshan.org>

;; emacs-jieba-rs is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; emacs-jieba-rs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with emacs-jieba-rs.  If not, see
;; <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Integration tests for the jieba-rs Emacs dynamic module.  The
;; module must be loaded before running these tests.

;;; Code:

(require 'ert)

(ert-deftest jieba-rs-segment-precise ()
  "Basic Chinese word segmentation in precise mode."
  (should (equal (jieba-rs-segment "我们中出了一个叛徒")
                 ["我们" "中" "出" "了" "一个" "叛徒"])))

(ert-deftest jieba-rs-segment-empty ()
  "Segmenting an empty string yields an empty vector."
  (should (equal (jieba-rs-segment "") [])))

(ert-deftest jieba-rs-segment-single-char ()
  "Segmenting a single Chinese character."
  (should (equal (jieba-rs-segment "我") ["我"])))

(ert-deftest jieba-rs-segment-ascii-mixed ()
  "Segmenting text with mixed CJK and ASCII."
  (should (equal (jieba-rs-segment "hello世界")
                 ["hello" "世界"])))

(ert-deftest jieba-rs-segment-long-text ()
  "Segmenting longer text yields a non-empty vector."
  (let ((vec (jieba-rs-segment "我爱北京天安门天安门上太阳升")))
    (should (vectorp vec))
    (should (> (length vec) 0))))

(ert-deftest jieba-rs-segment-return-type ()
  "jieba-rs-segment always returns a vector."
  (should (vectorp (jieba-rs-segment "测试")))
  (should (vectorp (jieba-rs-segment ""))))

(provide 'jieba-rs-tests)
;;; jieba-rs-tests.el ends here
