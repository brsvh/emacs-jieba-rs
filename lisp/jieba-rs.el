;;; jieba-rs.el --- Jieba Chinese segment -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Bingshan Chang <chang@bingshan.org>

;; Assisted-by: OpenCode:deepseek-v4-pro
;; Author: Bingshan Chang <chang@bingshan.org>
;; Keywords: chinese, segmentation
;; Package-Requires: ((emacs "30.1"))
;; Version: 0.1.0

;; This file is not part of GNU Emacs.

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation, either version 3 of the License,
;; or (at your option) any later version.

;; This file is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this file.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Jieba Chinese word segmentation for Emacs.
;;
;; Provides ~jieba-rs-mode~, a minor mode with commands to segment
;; Chinese text using the jieba-rs dynamic module.
;;
;; * Usage
;;
;; Toggle the mode in current buffer.
;;
;; #+begin_src emacs-lisp
;;   M-x jieba-rs-mode
;; #+end_src
;;
;; Segment the active region.
;;
;; #+begin_src emacs-lisp
;;   M-x jieba-rs-segment-region
;; #+end_src
;;
;; Segment the entire buffer.
;;
;; #+begin_src emacs-lisp
;;   M-x jieba-rs-segment-buffer
;; #+end_src
;;
;; Toggle word boundary display.
;;
;; #+begin_src emacs-lisp
;;   M-x jieba-rs-toggle-boundaries
;; #+end_src
;;
;; Toggle POS tag display.
;;
;; #+begin_src emacs-lisp
;;   M-x jieba-rs-toggle-tags
;; #+end_src
;;
;; * Customization
;;
;; ** ~jieba-rs-hmm~
;;
;; Enable HMM-based new word discovery.
;;
;; ** ~jieba-rs-segment-function~
;;
;; Choose the segmentation algorithm.
;;
;; ** ~jieba-rs-normalize-rules~
;;
;; Per-mode normalization rules for overlay positioning.
;;
;; ** ~jieba-rs-user-dict~
;;
;; Path to a user dictionary file, or nil to disable.

;;; Code:

(require 'cl-lib)

(declare-function jieba-rs-module-segment
                  "ext:jieba-rs-module" (text hmm))
(declare-function jieba-rs-module-segment-all
                  "ext:jieba-rs-module" (text))
(declare-function jieba-rs-module-segment-search
                  "ext:jieba-rs-module" (text hmm))
(declare-function jieba-rs-module-segment-tag
                  "ext:jieba-rs-module" (text hmm))
(declare-function jieba-rs-module-load-user-dict
                  "ext:jieba-rs-module" (path))
(declare-function jieba-rs-module-add-word
                  "ext:jieba-rs-module" (word freq tag))

(defgroup jieba-rs nil
  "Jieba Chinese word segmentation."
  :prefix "jieba-rs-"
  :group 'tools)

(defun jieba-rs--load-module ()
  "Load the native module if not already loaded."
  (unless (featurep 'jieba-rs-module)
    (let ((suffixes (list module-file-suffix)))
      (module-load
       (or (locate-file "jieba-rs-module" load-path suffixes)
           (when load-file-name
             (expand-file-name
              (concat "jieba-rs-module" module-file-suffix)
              (file-name-directory load-file-name)))
           (error "Cannot find jieba-rs-module%s"
                  module-file-suffix))))))

(defcustom jieba-rs-hmm t
  "When non-nil, enable HMM-based new word discovery."
  :type 'boolean
  :group 'jieba-rs)

(defcustom jieba-rs-user-dict
  (expand-file-name "jieba-rs/user.dict" user-emacs-directory)
  "Path to a user dictionary file, or nil to disable."
  :type '(choice (const :tag "None" nil)
                 (file :tag "Dictionary file"))
  :group 'jieba-rs)

(defun jieba-rs--load-user-dict ()
  "Load the user dictionary if `jieba-rs-user-dict' is set."
  (when (and jieba-rs-user-dict
             (file-exists-p jieba-rs-user-dict))
    (condition-case err
        (jieba-rs-module-load-user-dict
         (expand-file-name jieba-rs-user-dict))
      (error
       (display-warning 'jieba-rs
                        (format "Failed to load user dict: %s"
                                (error-message-string err))
                        :warning)))))

(defun jieba-rs-add-word (word &optional freq tag persist)
  "Add WORD to the Jieba dictionary.
FREQ is the word frequency; nil triggers auto-suggestion.
TAG is an optional POS tag.
With prefix arg PERSIST, append the entry to the user dict file."
  (interactive
   (list (read-string "Word: ")
         nil nil current-prefix-arg))
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (let ((f (jieba-rs-module-add-word word freq tag)))
    (when persist
      (unless jieba-rs-user-dict
        (user-error "Cannot persist: jieba-rs-user-dict is nil"))
      (let ((dir (file-name-directory
                  (expand-file-name jieba-rs-user-dict))))
        (unless (file-exists-p dir)
          (make-directory dir t)))
      (with-temp-buffer
        (insert (format "%s %d %s\n" word f (or tag "")))
        (write-region nil nil (expand-file-name jieba-rs-user-dict)
                      'append 'quiet)))
    f))

(defcustom jieba-rs-segment-function 'jieba-rs-module-segment
  "Segmentation function to use.
`jieba-rs-module-segment' uses precise mode (default).
`jieba-rs-module-segment-all' uses full mode,
scanning all possible cuts.
`jieba-rs-module-segment-search' uses search engine mode."
  :type '(choice (const :tag "Precise" jieba-rs-module-segment)
                 (const :tag "Full" jieba-rs-module-segment-all)
                 (const :tag "Search" jieba-rs-module-segment-search))
  :group 'jieba-rs)

(defcustom jieba-rs-normalize-rules
  '((t ("[\u0000-\u001f\u007f-\u009f\ufeff]"
        . " ")
       ("[\t\n\r\f　]"
        . " ")))
  "Normalization rules for text before overlay segmentation.
Each replacement must be exactly one space so that the
normalized text keeps the same length as the buffer text.
Each element is (MODE . RULES) where MODE is a major-mode symbol
or t for the default fallback.  RULES is a list of (REGEXP
. REPLACEMENT) pairs applied in order with \
`replace-regexp-in-string'."
  :type '(repeat
          (cons (choice (const t)
                        (symbol :tag "Major mode"))
                (repeat (cons (regexp :tag "Pattern")
                              (string :tag "Replacement")))))
  :group 'jieba-rs)

(defun jieba-rs--normalize-text (beg end)
  "Normalize text in region BEG..END for overlay segmentation.
Respects `jieba-rs-normalize-rules' for the current major mode."
  (let ((text (buffer-substring-no-properties beg end))
        (rules (cdr (or (cl-find major-mode
                                 jieba-rs-normalize-rules
                                 :test #'derived-mode-p
                                 :key #'car)
                        (assq t
                              jieba-rs-normalize-rules)))))
    (dolist (rule rules)
      (setq text (replace-regexp-in-string
                  (car rule) (cdr rule) text)))
    text))

(defun jieba-rs--segment-function-arity (fn)
  "Return the number of arguments FN expects.
`jieba-rs-module-segment-all' takes 1 argument (text only);
others take 2 (text hmm)."
  (if (eq fn 'jieba-rs-module-segment-all) 1 2))

(defun jieba-rs--call-segment (text)
  "Segment TEXT using `jieba-rs-segment-function'."
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (let* ((fn jieba-rs-segment-function)
         (arity (jieba-rs--segment-function-arity fn)))
    (if (= arity 1)
        (funcall fn text)
      (funcall fn text jieba-rs-hmm))))

(defun jieba-rs--format-words (words)
  "Return WORDS as a single string with | separators."
  (mapconcat #'identity words " | "))

(defun jieba-rs--show-buffer (words title)
  "Display WORDS in *jieba-rs-segment* buffer.
TITLE is shown as a header line followed by a separator."
  (let ((buf (get-buffer-create "*jieba-rs-segment*"))
        (text (jieba-rs--format-words words)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (special-mode)
        (insert title "\n"
                (make-string (string-width title) ?─) "\n\n")
        (insert text "\n")
        (goto-char (point-min))))
    (display-buffer buf)))

(defun jieba-rs--show-tooltip (text)
  "Show TEXT via `tooltip-show' when `tooltip-mode' is on.
In text terminals this falls back to the echo area."
  (if (and (bound-and-true-p tooltip-mode)
           (fboundp 'tooltip-show))
      (tooltip-show text)
    (message "%s" text)))

(defun jieba-rs-forward-word (&optional arg)
  "Move point forward ARG Chinese words."
  (interactive "^p")
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (let ((n (or arg 1)))
    (if (< n 0)
        (jieba-rs-backward-word (- n))
      (dotimes (_i n)
        (let* ((orig (point))
               ;; Always use precise mode for contiguous
               ;; word boundaries.
               (words (jieba-rs-module-segment
                       (buffer-substring-no-properties
                        (point) (point-max))
                       jieba-rs-hmm))
               (pos (point)))
          (catch 'done
            (dolist (word (append words nil))
              (setq pos (+ pos (length word)))
              (unless (string-blank-p word)
                (goto-char pos)
                (throw 'done t))))
          (when (= (point) orig)
            (goto-char (point-max))))))))

(defun jieba-rs-backward-word (&optional arg)
  "Move point backward ARG Chinese words."
  (interactive "^p")
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (let ((n (or arg 1)))
    (if (< n 0)
        (jieba-rs-forward-word (- n))
      (dotimes (_i n)
        (let ((words (append (jieba-rs-module-segment
                              (buffer-substring-no-properties
                               (point-min) (point))
                              jieba-rs-hmm)
                             nil))
              (target (point-min))
              (pos (point-min)))
          (dolist (word words)
            (let ((end (+ pos (length word))))
              (unless (string-blank-p word)
                (when (< pos (point))
                  (setq target pos)))
              (setq pos end)))
          (goto-char target))))))

(defun jieba-rs-forward-sentence (&optional arg)
  "Move point forward ARG Chinese sentences."
  (interactive "^p")
  (re-search-forward "[。！？\n]+" nil t (or arg 1)))

(defun jieba-rs-backward-sentence (&optional arg)
  "Move point backward ARG Chinese sentences."
  (interactive "^p")
  (re-search-backward "[。！？\n]+" nil t (or arg 1)))

(defface jieba-rs-boundary-face
  '((t :inherit shadow))
  "Face for word boundary separators."
  :group 'jieba-rs)

(defvar-local jieba-rs-boundaries-overlays nil
  "List of word boundary overlays in the current buffer.")

(defvar-local jieba-rs--boundaries-timer nil
  "Idle timer or `post-command-hook' for boundary refresh.")

(defun jieba-rs--clear-boundaries ()
  "Remove boundary overlays and cancel scheduled refresh."
  (mapc #'delete-overlay jieba-rs-boundaries-overlays)
  (remove-hook 'after-change-functions
               #'jieba-rs--boundaries-after-change t)
  (when jieba-rs--boundaries-timer
    (cancel-timer jieba-rs--boundaries-timer))
  (remove-hook 'post-command-hook
               #'jieba-rs--refresh-boundaries t)
  (setq jieba-rs-boundaries-overlays nil
        jieba-rs--boundaries-timer nil))

(defun jieba-rs--boundaries-after-change (&rest _)
  "Clear boundaries and schedule a visible-window refresh."
  (jieba-rs--clear-boundaries)
  (add-hook 'after-change-functions
            #'jieba-rs--boundaries-after-change nil t)
  (if (> (buffer-size) 10000)
      (let ((buf (current-buffer)))
        (setq jieba-rs--boundaries-timer
              (run-with-idle-timer
               0.15 nil
               (lambda ()
                 (when (buffer-live-p buf)
                   (with-current-buffer buf
                     (jieba-rs--refresh-boundaries)))))))
    (add-hook 'post-command-hook
              #'jieba-rs--refresh-boundaries nil t)))

(defun jieba-rs--refresh-boundaries ()
  "Rebuild boundary overlays for the visible window."
  (remove-hook 'post-command-hook
               #'jieba-rs--refresh-boundaries t)
  (setq jieba-rs--boundaries-timer nil)
  (jieba-rs--show-boundaries))

(defun jieba-rs--show-boundaries ()
  "Show word boundaries in the current buffer."
  (let* ((beg (point-min))
         (end (save-excursion
                (goto-char (point-max))
                (skip-chars-backward " \t\n\r\f　")
                (point)))
         (win-start (window-start))
         (win-end (window-end))
         (text (jieba-rs--normalize-text beg end))
         (pos beg))
    (unless (and win-end (> win-end win-start))
      (setq win-start beg
            win-end end))
    (dolist (word (append (jieba-rs-module-segment
                           text jieba-rs-hmm)
                          nil))
      (setq pos (+ pos (length word)))
      (when (and (not (string-blank-p word))
                 (< pos end)
                 (>= pos win-start)
                 (< pos win-end))
        (let ((ov (make-overlay pos pos)))
          (overlay-put ov 'priority 0)
          (overlay-put ov 'after-string
                       (propertize " │ "
                                   'face
                                   'jieba-rs-boundary-face))
          (push ov jieba-rs-boundaries-overlays)))))
  (add-hook 'after-change-functions
            #'jieba-rs--boundaries-after-change nil t))

;;;###autoload
(defun jieba-rs-toggle-boundaries ()
  "Toggle display of word segmentation boundaries."
  (interactive)
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (if jieba-rs-boundaries-overlays
      (jieba-rs--clear-boundaries)
    (jieba-rs--show-boundaries)))

(defconst jieba-rs-tag-names
  '(("n" . "noun") ("nr" . "propn") ("ns" . "propn")
    ("nt" . "propn") ("nz" . "propn") ("v" . "verb")
    ("vd" . "verb") ("vn" . "verb") ("a" . "adj")
    ("ad" . "adj") ("an" . "adj") ("d" . "adv")
    ("r" . "pron") ("p" . "adp") ("c" . "cconj")
    ("u" . "part") ("m" . "num") ("q" . "num")
    ("f" . "noun") ("t" . "noun") ("s" . "noun")
    ("z" . "adj") ("w" . "punct") ("x" . "sym")
    ("b" . "noun") ("e" . "intj") ("y" . "part")
    ("o" . "intj") ("h" . "noun") ("k" . "noun")
    ("i" . "noun") ("l" . "noun") ("j" . "noun"))
  "Alist mapping ICTCLAS POS codes to Universal Dependencies tags.")

(defface jieba-rs-tag-face
  '((t :inherit font-lock-keyword-face :slant italic))
  "Face for POS tag annotations."
  :group 'jieba-rs)

(defvar-local jieba-rs-tag-overlays nil
  "List of POS tag overlays in the current buffer.")

(defvar-local jieba-rs--tags-timer nil
  "Idle timer or `post-command-hook' for tag refresh.")

(defun jieba-rs--clear-tags ()
  "Remove tag overlays and cancel scheduled refresh."
  (mapc #'delete-overlay jieba-rs-tag-overlays)
  (remove-hook 'after-change-functions
               #'jieba-rs--tags-after-change t)
  (when jieba-rs--tags-timer
    (cancel-timer jieba-rs--tags-timer))
  (remove-hook 'post-command-hook
               #'jieba-rs--refresh-tags t)
  (setq jieba-rs-tag-overlays nil
        jieba-rs--tags-timer nil))

(defun jieba-rs--tags-after-change (&rest _)
  "Clear tags and schedule a visible-window refresh."
  (jieba-rs--clear-tags)
  (add-hook 'after-change-functions
            #'jieba-rs--tags-after-change nil t)
  (if (> (buffer-size) 10000)
      (let ((buf (current-buffer)))
        (setq jieba-rs--tags-timer
              (run-with-idle-timer
               0.15 nil
               (lambda ()
                 (when (buffer-live-p buf)
                   (with-current-buffer buf
                     (jieba-rs--refresh-tags)))))))
    (add-hook 'post-command-hook
              #'jieba-rs--refresh-tags nil t)))

(defun jieba-rs--refresh-tags ()
  "Rebuild tag overlays for the visible window."
  (remove-hook 'post-command-hook
               #'jieba-rs--refresh-tags t)
  (setq jieba-rs--tags-timer nil)
  (jieba-rs--show-tags))

(defun jieba-rs--show-tags ()
  "Show POS tags in the current buffer."
  (let* ((beg (point-min))
         (end (save-excursion
                (goto-char (point-max))
                (skip-chars-backward " \t\n\r\f　")
                (point)))
         (win-start (window-start))
         (win-end (window-end))
         (text (jieba-rs--normalize-text beg end))
         (pos beg))
    (unless (and win-end (> win-end win-start))
      (setq win-start beg
            win-end end))
    (dolist (tag (append (jieba-rs-module-segment-tag
                          text jieba-rs-hmm)
                         nil))
      (let* ((word (plist-get tag :word))
             (cat (plist-get tag :category))
             (end-pos (+ pos (length word)))
             (ud (or (cdr (assoc cat jieba-rs-tag-names))
                     cat)))
        (when (and (not (string-blank-p word))
                   (< end-pos end)
                   (>= end-pos win-start)
                   (< end-pos win-end))
          (let ((ov (make-overlay end-pos end-pos)))
            (overlay-put ov 'priority 1)
            (overlay-put ov 'after-string
                         (propertize ud
                                     'display '(raise -0.3)
                                     'face
                                     'jieba-rs-tag-face))
            (push ov jieba-rs-tag-overlays)))
        (setq pos end-pos))))
  (add-hook 'after-change-functions
            #'jieba-rs--tags-after-change nil t))

;;;###autoload
(defun jieba-rs-toggle-tags ()
  "Toggle display of part-of-speech tags."
  (interactive)
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (if jieba-rs-tag-overlays
      (jieba-rs--clear-tags)
    (jieba-rs--show-tags)))

;;;###autoload
(defun jieba-rs-segment-region (start end)
  "Segment the region from START to END.
Display results in a buffer and show a tooltip at START
when `tooltip-mode' is enabled."
  (interactive "r")
  (let* ((text (buffer-substring-no-properties start end))
         (words (jieba-rs--call-segment text))
         (title (format "Region %d..%d — %s"
                        start end
                        jieba-rs-segment-function)))
    (jieba-rs--show-buffer words title)
    (save-excursion
      (goto-char start)
      (jieba-rs--show-tooltip (jieba-rs--format-words words)))))

;;;###autoload
(defun jieba-rs-segment-buffer ()
  "Segment the entire buffer (respecting narrowing).
Display results in a buffer."
  (interactive)
  (let* ((text (buffer-substring-no-properties
                (point-min) (point-max)))
         (words (jieba-rs--call-segment text))
         (title (format "Buffer %s — %s"
                        (buffer-name)
                        jieba-rs-segment-function)))
    (jieba-rs--show-buffer words title)))

(defvar jieba-rs-mode-map
  (let ((map (make-sparse-keymap)))
    (keymap-set map "<remap> <forward-word>"
                #'jieba-rs-forward-word)
    (keymap-set map "<remap> <backward-word>"
                #'jieba-rs-backward-word)
    (keymap-set map "<remap> <forward-sentence>"
                #'jieba-rs-forward-sentence)
    (keymap-set map "<remap> <backward-sentence>"
                #'jieba-rs-backward-sentence)
    map)
  "Keymap for `jieba-rs-mode'.")

;;;###autoload
(define-minor-mode jieba-rs-mode
  "Toggle Jieba Chinese word segmentation mode.

When enabled, provides commands to segment Chinese text using
the jieba-rs dynamic module.  Use `jieba-rs-segment-function'
to choose the segmentation algorithm.

\\{jieba-rs-mode-map}"
  :lighter " Jieba"
  :keymap jieba-rs-mode-map
  :group 'jieba-rs
  (when jieba-rs-mode
    (condition-case err
        (progn
          (jieba-rs--load-module)
          (jieba-rs--load-user-dict))
      (error
       (display-warning 'jieba-rs
                        (format "Failed to load module: %s"
                                (error-message-string err))
                        :error)
       (jieba-rs-mode -1)))))

(provide 'jieba-rs)
;;; jieba-rs.el ends here
