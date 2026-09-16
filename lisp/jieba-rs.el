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
;; Extract keywords by TextRank.
;;
;; #+begin_src emacs-lisp
;;   M-x jieba-rs-extract-keywords-region
;; #+end_src
;;
;; Extract keywords from the entire buffer.
;;
;; #+begin_src emacs-lisp
;;   M-x jieba-rs-extract-keywords-buffer
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
;; ** ~jieba-rs-boundary-separator~
;;
;; String inserted between words as a boundary marker.
;;
;; ** ~jieba-rs-extract-function~
;;
;; Choose the extraction algorithm: tfidf (default), textrank,
;; or precise.
;;
;; ** ~jieba-rs-user-dict~
;;
;; Path to a user dictionary file, or nil to disable.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

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
(declare-function jieba-rs-module-extract-keywords
                  "ext:jieba-rs-module" (text top_k method))

(declare-function jieba-rs-module-dictionary-version
                  "ext:jieba-rs-module" ())

(defgroup jieba-rs nil
  "Jieba Chinese word segmentation."
  :prefix "jieba-rs-"
  :group 'tools)

(defun jieba-rs--set-display-option (symbol value)
  "Set the default of SYMBOL to VALUE and refresh affected displays."
  (set-default symbol value)
  (when (fboundp 'jieba-rs--refresh-display-configuration)
    (dolist (buffer (buffer-list))
      (with-current-buffer buffer
        (jieba-rs--refresh-display-configuration)))))

(defcustom jieba-rs-hmm t
  "When non-nil, enable HMM-based new word discovery."
  :set #'jieba-rs--set-display-option
  :type 'boolean
  :group 'jieba-rs)

(defcustom jieba-rs-user-dict
  (expand-file-name "jieba-rs/user.dict" user-emacs-directory)
  "Path to a user dictionary file, or nil to disable."
  :type '(choice (const :tag "None" nil)
                 (file :tag "Dictionary file"))
  :group 'jieba-rs)

(defvar jieba-rs--loaded-user-dicts (make-hash-table :test #'equal)
  "File states of dictionaries successfully loaded in this session.")

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
  :set #'jieba-rs--set-display-option
  :type '(repeat
          (cons (choice (const t)
                        (symbol :tag "Major mode"))
                (repeat (cons (regexp :tag "Pattern")
                              (string :tag "Replacement")))))
  :group 'jieba-rs)

(defcustom jieba-rs-extract-function 'tfidf
  "Extraction function to use with keyword extraction commands.
`tfidf' uses TF-IDF keyword extraction.
`textrank' uses TextRank keyword extraction.
`precise' uses precise word segmentation."
  :type '(choice (const :tag "TF-IDF" tfidf)
                 (const :tag "TextRank" textrank)
                 (const :tag "Precise segmentation" precise))
  :group 'jieba-rs)

(defcustom jieba-rs-boundary-separator "  "
  "String inserted between words as a boundary marker."
  :set #'jieba-rs--set-display-option
  :type 'string
  :group 'jieba-rs)

(defcustom jieba-rs-max-display-line-length 10000
  "Maximum characters per line to segment for boundary and POS displays.
Longer lines are skipped to keep idle refreshes responsive after editing.
The count excludes the terminating newline and respects narrowing.
Set to nil to display lines of any length, which may delay Emacs.
Word motion and explicit segmentation commands always use the full text."
  :set #'jieba-rs--set-display-option
  :type '(choice (const :tag "Unlimited" nil)
                 (natnum :tag "Maximum characters"))
  :group 'jieba-rs)

(defface jieba-rs-boundary-face
  '((t :inherit shadow))
  "Face for word boundary separators."
  :group 'jieba-rs)

(defface jieba-rs-tag-face
  '((t :inherit font-lock-keyword-face :slant italic))
  "Face for POS tag annotations."
  :group 'jieba-rs)

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

(defvar-local jieba-rs--segment-cache nil
  "Cached line bounds and segmentation results.")

(defvar-local jieba-rs--segment-cache-context nil
  "Buffer, configuration and dictionary state of cached results.")

(defvar-local jieba-rs--segment-cache-limit 128
  "Number of cached results to retain for the visible working set.")

(defvar-local jieba-rs--segment-cache-clock 0
  "Sequence number of the last segmentation cache access.")

(defvar-local jieba-rs--content-end-cache nil
  "Last nonblank end, keyed by text modification tick and accessible bounds.")

(defvar-local jieba-rs--boundaries-enabled nil
  "Whether boundary display is enabled in this buffer.")

(defvar-local jieba-rs--tags-enabled nil
  "Whether part-of-speech display is enabled in this buffer.")

(defvar-local jieba-rs--display-restriction nil
  "Accessible bounds observed by the enabled displays.")

(defvar-local jieba-rs--display-configuration nil
  "Options observed by the enabled displays.")

(defvar-local jieba-rs-boundaries-overlays nil
  "List of word boundary overlays in the current buffer.")

(defvar-local jieba-rs--boundaries-timer nil
  "Pending idle timer for boundary refresh.")

(defvar-local jieba-rs-tag-overlays nil
  "List of POS tag overlays in the current buffer.")

(defvar-local jieba-rs--tags-timer nil
  "Pending idle timer for tag refresh.")

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

(defun jieba-rs--dictionary-file-state (file)
  "Return FILE's identity, size and change times, or nil if unavailable."
  (when-let* ((attributes (file-attributes file)))
    (list (file-attribute-device-number attributes)
          (file-attribute-inode-number attributes)
          (file-attribute-size attributes)
          (file-attribute-modification-time attributes)
          (file-attribute-status-change-time attributes))))

(defun jieba-rs--load-user-dict (&optional force)
  "Load a configured user dictionary when its file changes.
With FORCE, reload unchanged files and propagate errors."
  (when (and jieba-rs-user-dict
             (file-exists-p jieba-rs-user-dict))
    (condition-case err
        (let* ((file (file-truename jieba-rs-user-dict))
               (state (jieba-rs--dictionary-file-state file)))
          (when (or force (not state)
                    (not (equal state (gethash file jieba-rs--loaded-user-dicts))))
            (jieba-rs-module-load-user-dict file)
            (jieba-rs--refresh-dictionary-displays)
            ;; A concurrently edited file must be retried next time.
            (if (and state (equal state (jieba-rs--dictionary-file-state file)))
                (puthash file state jieba-rs--loaded-user-dicts)
              (remhash file jieba-rs--loaded-user-dicts))))
      (error
       (if force
           (signal (car err) (cdr err))
         (display-warning 'jieba-rs
                          (format "Failed to load user dict: %s"
                                  (error-message-string err))
                          :warning))))))

;;;###autoload
(defun jieba-rs-reload-user-dict ()
  "Reload the configured user dictionary even when its file is unchanged."
  (interactive)
  (unless (and jieba-rs-user-dict (file-exists-p jieba-rs-user-dict))
    (user-error "No existing Jieba user dictionary configured"))
  (jieba-rs--load-module)
  (jieba-rs--load-user-dict t))

(defun jieba-rs--normalize-text (beg end)
  "Normalize text in region BEG..END for overlay segmentation.
Respects `jieba-rs-normalize-rules' for the current major mode."
  (let ((text (buffer-substring-no-properties beg end))
        (rules (cdr (or (cl-find-if
                         (lambda (entry)
                           (and (not (eq (car entry) t))
                                (derived-mode-p (car entry))))
                         jieba-rs-normalize-rules)
                        (assq t jieba-rs-normalize-rules)))))
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

(defun jieba-rs--display-extract-results (items title)
  "Display ITEMS in *jieba-rs-extract* buffer with TITLE."
  (let ((buf (get-buffer-create "*jieba-rs-extract*"))
        (formatter (if (eq jieba-rs-extract-function
                           'precise)
                       (lambda (item) item)
                     (lambda (item)
                       (format "%s  %s"
                               (plist-get item :keyword)
                               (plist-get item :weight))))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (special-mode)
        (insert title "\n"
                (make-string (string-width title)
                             ?─) "\n\n")
        (dolist (item (append items nil))
          (insert (funcall formatter item) "\n"))
        (goto-char (point-min))))
    (display-buffer buf)))

(defun jieba-rs--trim-segment-cache ()
  "Discard least recently used results exceeding the cache limit."
  (when jieba-rs--segment-cache
    (let ((excess (- (hash-table-count jieba-rs--segment-cache)
                     jieba-rs--segment-cache-limit)))
      (when (> excess 0)
        (let (entries)
          (maphash (lambda (key line)
                     (push (cons key (aref line 3)) entries))
                   jieba-rs--segment-cache)
          (setq entries (sort entries (lambda (a b) (< (cdr a) (cdr b)))))
          (dotimes (_ excess)
            (remhash (car (pop entries)) jieba-rs--segment-cache)))))))

(defun jieba-rs--line-tokens (position &optional tagged normalized)
  "Return cached line bounds and tokens around POSITION.
TAGGED requests POS categories; NORMALIZED applies overlay rules.
Each token is a vector of start, end, word and optional category."
  (let ((context (list (buffer-chars-modified-tick)
                       (point-min) (point-max) jieba-rs-hmm major-mode
                       jieba-rs-normalize-rules
                       (jieba-rs-module-dictionary-version))))
    (unless (equal context jieba-rs--segment-cache-context)
      (setq jieba-rs--segment-cache-context (copy-tree context)
            jieba-rs--segment-cache-clock 0
            jieba-rs--segment-cache (make-hash-table :test #'equal))))
  (save-excursion
    (goto-char position)
    (let* ((beg (line-beginning-position))
           (end (min (point-max) (1+ (line-end-position))))
           (key (list beg end tagged normalized))
           (cached (gethash key jieba-rs--segment-cache))
           (line
            (or cached
                (let* ((text (if normalized (jieba-rs--normalize-text beg end)
                               (buffer-substring-no-properties beg end)))
                       (items (if tagged
                                  (jieba-rs-module-segment-tag text jieba-rs-hmm)
                                (jieba-rs-module-segment text jieba-rs-hmm)))
                       (tokens (make-vector (length items) nil))
                       (pos beg))
                  (dotimes (i (length items))
                    (let* ((item (aref items i))
                           (word (if tagged (plist-get item :word) item))
                           (next (+ pos (length word))))
                      (aset tokens i
                            (vector pos next word
                                    (when tagged (plist-get item :category))))
                      (setq pos next)))
                  (vector beg end tokens 0)))))
      (aset line 3 (cl-incf jieba-rs--segment-cache-clock))
      (unless cached
        (puthash key line jieba-rs--segment-cache)
        (jieba-rs--trim-segment-cache))
      line)))

(defun jieba-rs--visible-range (&optional window)
  "Return WINDOW's visible range, or the accessible range if undisplayed."
  (let* ((window (or window (get-buffer-window nil t)))
         (beg (if window (window-start window) (point-min)))
         (end (if window (window-end window t) (point-max))))
    (if (and end (> end beg))
        (cons (max beg (point-min)) (min end (point-max)))
      (cons (point-min) (point-max)))))

(defun jieba-rs--visible-ranges ()
  "Return the union of visible ranges in windows showing this buffer."
  (if-let* ((windows (get-buffer-window-list nil nil t)))
      (let ((ranges (sort (mapcar #'jieba-rs--visible-range windows)
                          (lambda (a b) (< (car a) (car b)))))
            merged)
        (dolist (range ranges)
          (if (and merged (<= (car range) (cdar merged)))
              (setcdr (car merged) (max (cdar merged) (cdr range)))
            (push range merged)))
        (nreverse merged))
    (list (jieba-rs--visible-range))))

(defun jieba-rs--content-end ()
  "Return the accessible end without trailing whitespace, using a cache."
  (let ((context (list (buffer-chars-modified-tick) (point-min) (point-max))))
    (unless (equal context (car jieba-rs--content-end-cache))
      (setq jieba-rs--content-end-cache
            (cons context
                  (save-excursion
                    (goto-char (point-max))
                    (skip-chars-backward " \t\n\r\f　")
                    (point)))))
    (cdr jieba-rs--content-end-cache)))

(defun jieba-rs--map-visible-tokens (function &optional tagged)
  "Call FUNCTION for visible normalized tokens, optionally TAGGED."
  (let* ((ranges (jieba-rs--visible-ranges))
         (content-end (jieba-rs--content-end)))
    ;; Retain raw motion, normalized boundaries and tags for each line.
    (setq jieba-rs--segment-cache-limit
          (max 128 (* 3 (cl-loop for (beg . end) in ranges
                                 sum (count-lines beg end)))))
    (dolist (range ranges)
      (let ((beg (car range))
            (end (cdr range)))
        (save-excursion
          (goto-char beg)
          (while (< (point) end)
            (let ((line-end (line-end-position)))
              (unless (and jieba-rs-max-display-line-length
                           (> (- line-end (line-beginning-position))
                              jieba-rs-max-display-line-length))
                (let* ((line (jieba-rs--line-tokens (point) tagged t))
                       (tokens (aref line 2))
                       (limit (min end content-end)))
                  (cl-loop for index from (jieba-rs--token-index tokens (1- beg) nil)
                           below (length tokens)
                           for token = (aref tokens index)
                           for pos = (aref token 1)
                           while (if tagged (<= pos limit) (< pos limit))
                           unless (string-blank-p (aref token 2))
                           do (funcall function token))))
              (goto-char (min (point-max) (1+ line-end))))))))
    (jieba-rs--trim-segment-cache)))

(defun jieba-rs--token-index (tokens position backward)
  "Find the token in TOKENS reachable from POSITION moving BACKWARD."
  (let ((low 0)
        (high (length tokens)))
    (while (< low high)
      (let* ((mid (/ (+ low high) 2))
             (token (aref tokens mid)))
        (if (if backward (< (aref token 0) position)
              (<= (aref token 1) position))
            (setq low (1+ mid))
          (setq high mid))))
    (if backward (1- low) low)))

(defun jieba-rs--move-word (count)
  "Move COUNT words using cached boundaries of complete lines."
  (let ((backward (< count 0))
        (remaining (abs count)))
    (while (and (> remaining 0)
                (if backward (> (point) (point-min))
                  (< (point) (point-max))))
      (let* ((position (if (and backward (bolp)) (1- (point)) (point)))
             (line (jieba-rs--line-tokens position))
             (tokens (aref line 2))
             (index (jieba-rs--token-index tokens (point) backward)))
        (while (and (> remaining 0) (>= index 0) (< index (length tokens)))
          (let ((token (aref tokens index)))
            (unless (string-blank-p (aref token 2))
              (goto-char (aref token (if backward 0 1)))
              (setq remaining (1- remaining))))
          (setq index (+ index (if backward -1 1))))
        (when (> remaining 0)
          (goto-char (aref line (if backward 0 1))))))))

(defun jieba-rs--update-display-hooks ()
  "Keep refresh and cleanup hooks consistent with display state."
  (if (or jieba-rs--boundaries-enabled jieba-rs--tags-enabled)
      (unless jieba-rs--display-configuration
        (setq jieba-rs--display-configuration
              (copy-tree (jieba-rs--display-options))))
    (setq jieba-rs--display-configuration nil))
  (setq jieba-rs--display-restriction
        (when (or jieba-rs--boundaries-enabled jieba-rs--tags-enabled)
          (cons (point-min) (point-max))))
  (dolist (entry
           '((jieba-rs--boundaries-enabled after-change-functions
                                           jieba-rs--boundaries-after-change)
             (jieba-rs--boundaries-enabled window-scroll-functions
                                           jieba-rs--boundaries-window-scroll)
             (jieba-rs--tags-enabled after-change-functions
                                     jieba-rs--tags-after-change)
             (jieba-rs--tags-enabled window-scroll-functions
                                     jieba-rs--tags-window-scroll)))
    (if (symbol-value (car entry))
        (add-hook (nth 1 entry) (nth 2 entry) nil t)
      (remove-hook (nth 1 entry) (nth 2 entry) t)))
  (dolist (entry
           '((post-command-hook . jieba-rs--post-command-scroll-check)
             (window-buffer-change-functions . jieba-rs--window-change)
             (window-size-change-functions . jieba-rs--window-change)
             (change-major-mode-hook . jieba-rs--clear-display)
             (kill-buffer-hook . jieba-rs--clear-display)))
    (if (or jieba-rs--boundaries-enabled jieba-rs--tags-enabled)
        (add-hook (car entry) (cdr entry) nil t)
      (remove-hook (car entry) (cdr entry) t))))

(defun jieba-rs--clear-display ()
  "Disable both displays and cancel their pending refreshes."
  (jieba-rs--clear-boundaries)
  (jieba-rs--clear-tags)
  (setq jieba-rs--segment-cache nil
        jieba-rs--content-end-cache nil
        jieba-rs--segment-cache-context nil
        jieba-rs--segment-cache-limit 128
        jieba-rs--segment-cache-clock 0))

(defun jieba-rs--refresh-dictionary-displays ()
  "Clear stale displays and schedule refreshes after a dictionary change."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when jieba-rs--boundaries-enabled
        (jieba-rs--boundaries-after-change))
      (when jieba-rs--tags-enabled
        (jieba-rs--tags-after-change)))))

(defun jieba-rs--window-change (window)
  "Refresh enabled displays after WINDOW changes its buffer or size."
  (with-current-buffer (window-buffer window)
    (when jieba-rs--boundaries-enabled
      (jieba-rs--schedule-refresh 'boundaries window))
    (when jieba-rs--tags-enabled
      (jieba-rs--schedule-refresh 'tags window))))

(defun jieba-rs--run-refresh (buffer window function timer-variable)
  "Refresh BUFFER in WINDOW using FUNCTION and clear TIMER-VARIABLE."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (set timer-variable nil)
      (let ((target (if (and (window-live-p window)
                             (eq (window-buffer window) buffer))
                        window
                      (get-buffer-window buffer t))))
        (when (and target
                   (if (eq timer-variable 'jieba-rs--boundaries-timer)
                       jieba-rs--boundaries-enabled
                     jieba-rs--tags-enabled))
          (with-selected-window target
            (funcall function)))))))

(defun jieba-rs--schedule-refresh (kind &optional window delay)
  "Schedule a refresh of KIND in WINDOW after idle DELAY seconds."
  (setq jieba-rs--display-restriction (cons (point-min) (point-max)))
  (let* ((boundaries (eq kind 'boundaries))
         (timer-variable (if boundaries 'jieba-rs--boundaries-timer
                           'jieba-rs--tags-timer))
         (function (if boundaries #'jieba-rs--refresh-boundaries
                     #'jieba-rs--refresh-tags)))
    (when (symbol-value timer-variable)
      (cancel-timer (symbol-value timer-variable)))
    (set timer-variable
         (run-with-idle-timer
          (or delay 0) nil #'jieba-rs--run-refresh
          (current-buffer) (or window (get-buffer-window nil t))
          function timer-variable))))

(defun jieba-rs--delete-display-overlays (overlays-variable timer-variable)
  "Clear OVERLAYS-VARIABLE and cancel its pending TIMER-VARIABLE."
  (mapc #'delete-overlay (symbol-value overlays-variable))
  (when (symbol-value timer-variable)
    (cancel-timer (symbol-value timer-variable)))
  (set overlays-variable nil)
  (set timer-variable nil))

(defun jieba-rs--clear-boundaries ()
  "Disable boundaries display and cancel scheduled refresh."
  (jieba-rs--delete-display-overlays
   'jieba-rs-boundaries-overlays 'jieba-rs--boundaries-timer)
  (setq jieba-rs--boundaries-enabled nil)
  (jieba-rs--update-display-hooks))

(defun jieba-rs--boundaries-after-change (&rest _)
  "Clear boundaries and schedule a visible-window refresh."
  (jieba-rs--delete-display-overlays
   'jieba-rs-boundaries-overlays 'jieba-rs--boundaries-timer)
  (jieba-rs--schedule-refresh
   'boundaries nil (if (> (buffer-size) 10000) 0.15 0)))

(defun jieba-rs--boundaries-window-scroll (window _new-start)
  "Schedule a boundaries refresh when WINDOW scrolls."
  (when jieba-rs--boundaries-enabled
    (jieba-rs--schedule-refresh 'boundaries window)))

(defun jieba-rs--refresh-boundaries ()
  "Rebuild boundary overlays for all windows showing this buffer."
  (jieba-rs--show-boundaries))

(defun jieba-rs--show-boundaries ()
  "Show word boundaries in the current buffer."
  (jieba-rs--show-display nil))

(defun jieba-rs--clear-tags ()
  "Disable tags display and cancel scheduled refresh."
  (jieba-rs--delete-display-overlays
   'jieba-rs-tag-overlays 'jieba-rs--tags-timer)
  (setq jieba-rs--tags-enabled nil)
  (jieba-rs--update-display-hooks))

(defun jieba-rs--tags-after-change (&rest _)
  "Clear tags and schedule a visible-window refresh."
  (jieba-rs--delete-display-overlays
   'jieba-rs-tag-overlays 'jieba-rs--tags-timer)
  (jieba-rs--schedule-refresh
   'tags nil (if (> (buffer-size) 10000) 0.15 0)))

(defun jieba-rs--refresh-tags ()
  "Rebuild tag overlays for all windows showing this buffer."
  (jieba-rs--show-tags))

(defun jieba-rs--tags-window-scroll (window _new-start)
  "Schedule a tags refresh when WINDOW scrolls."
  (when jieba-rs--tags-enabled
    (jieba-rs--schedule-refresh 'tags window)))

(defun jieba-rs--show-tags ()
  "Show POS tags in the current buffer."
  (jieba-rs--show-display t))

(defun jieba-rs--show-display (tagged)
  "Rebuild a complete display, with POS labels when TAGGED is non-nil.
On failure, discard partial overlays and retain the previous enabled state
so an already enabled display can retry after the text is corrected."
  (let ((overlays-variable (if tagged 'jieba-rs-tag-overlays
                             'jieba-rs-boundaries-overlays))
        (timer-variable (if tagged 'jieba-rs--tags-timer
                          'jieba-rs--boundaries-timer))
        (enabled-variable (if tagged 'jieba-rs--tags-enabled
                            'jieba-rs--boundaries-enabled))
        complete)
    (jieba-rs--delete-display-overlays overlays-variable timer-variable)
    (unwind-protect
        (progn
          (jieba-rs--map-visible-tokens
           (lambda (token)
             (let* ((pos (aref token 1))
                    (ov (make-overlay pos pos)))
               (set overlays-variable (cons ov (symbol-value overlays-variable)))
               (overlay-put ov 'priority (if tagged 1 0))
               (overlay-put
                ov 'after-string
                (if tagged
                    (let* ((cat (aref token 3))
                           (label (or (cdr (assoc cat jieba-rs-tag-names)) cat)))
                      (propertize label 'display '(raise -0.3)
                                  'face 'jieba-rs-tag-face))
                  (propertize jieba-rs-boundary-separator
                              'face 'jieba-rs-boundary-face)))))
           tagged)
          (set enabled-variable t)
          (setq complete t))
      (unless complete
        (jieba-rs--delete-display-overlays overlays-variable timer-variable))
      (jieba-rs--update-display-hooks))))

(defun jieba-rs--display-options ()
  "Return the configuration affecting this buffer's displays."
  (list jieba-rs-hmm jieba-rs-normalize-rules
        jieba-rs-boundary-separator jieba-rs-max-display-line-length))

(defun jieba-rs--refresh-display-configuration ()
  "Clear stale displays and schedule a refresh when options change."
  (when (or jieba-rs--boundaries-enabled jieba-rs--tags-enabled)
    (let ((options (jieba-rs--display-options)))
      (unless (equal options jieba-rs--display-configuration)
        (setq jieba-rs--display-configuration (copy-tree options))
        (when jieba-rs--boundaries-enabled
          (jieba-rs--boundaries-after-change))
        (when jieba-rs--tags-enabled
          (jieba-rs--tags-after-change))))))

(defun jieba-rs--post-command-scroll-check ()
  "Schedule refreshes after commands that change the view."
  (jieba-rs--refresh-display-configuration)
  (when (or (not (equal jieba-rs--display-restriction
                        (cons (point-min) (point-max))))
            (memq this-command
                  '(recenter recenter-top-bottom
                             beginning-of-buffer end-of-buffer)))
    (setq jieba-rs--display-restriction (cons (point-min) (point-max)))
    (when jieba-rs--boundaries-enabled
      (jieba-rs--schedule-refresh 'boundaries))
    (when jieba-rs--tags-enabled
      (jieba-rs--schedule-refresh 'tags))))

(defun jieba-rs--append-word (file word freq tag)
  "Append WORD with FREQ and TAG as a separate record in FILE."
  (with-temp-buffer
    (let ((size (when (file-exists-p file)
                  (file-attribute-size (file-attributes file)))))
      (when (and size (> size 0))
        (insert-file-contents-literally file nil (1- size) size))
      (let ((needs-newline (and (> (buffer-size) 0)
                                (not (eq (char-before (point-max)) ?\n)))))
        (erase-buffer)
        (when needs-newline (insert "\n"))))
    (insert (format "%s %d%s\n" word freq
                    (if tag (concat " " tag) "")))
    (let ((coding-system-for-write 'utf-8-unix))
      (write-region nil nil file 'append 'quiet))))

(defconst jieba-rs--dictionary-field-separator-regexp
  (concat "[\0\t-\r \u0085\u00a0\u1680\u2000-\u200a"
          "\u2028\u2029\u202f\u205f\u3000]")
  "NUL and Unicode White_Space characters forbidden in saved fields.
The whitespace set matches Rust's `str::split_whitespace' independently
of the current buffer's syntax table.")

(defun jieba-rs-add-word (word &optional freq tag persist)
  "Add WORD to the Jieba dictionary.
FREQ is the word frequency; nil triggers auto-suggestion.
TAG is an optional POS tag.
With prefix arg PERSIST, append the entry to the user dict file.
A saved TAG must be nil or a nonempty single field.
If writing the file fails, WORD remains available for this session."
  (interactive
   (list (read-string "Word: ")
         nil nil current-prefix-arg))
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (let ((file (when persist
                (unless jieba-rs-user-dict
                  (user-error "Cannot persist: jieba-rs-user-dict is nil"))
                (unless (and (stringp word) (not (string-empty-p word))
                             (not (string-match-p
                                   jieba-rs--dictionary-field-separator-regexp
                                   word))
                             (or (null tag)
                                 (and (stringp tag)
                                      (not (string-empty-p tag))
                                      (not (string-match-p
                                            jieba-rs--dictionary-field-separator-regexp
                                            tag)))))
                  (user-error "Dictionary words and tags must be single fields"))
                (expand-file-name jieba-rs-user-dict))))
    (when file
      (make-directory (file-name-directory file) t))
    (let ((f (jieba-rs-module-add-word word freq tag)))
      (jieba-rs--refresh-dictionary-displays)
      (when file
        (jieba-rs--append-word file word f tag))
      f)))

(defun jieba-rs-forward-word (&optional arg)
  "Move point forward ARG Chinese words."
  (interactive "^p")
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (jieba-rs--move-word (or arg 1)))

(defun jieba-rs-backward-word (&optional arg)
  "Move point backward ARG Chinese words."
  (interactive "^p")
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (jieba-rs--move-word (- (or arg 1))))

(defun jieba-rs-forward-sentence (&optional arg)
  "Move point forward ARG Chinese sentences.
An unterminated final sentence ends at the accessible buffer end."
  (interactive "^p")
  (let ((n (or arg 1)))
    (if (< n 0)
        (jieba-rs-backward-sentence (- n))
      (dotimes (_ n)
        (skip-chars-forward " \t\n\r\f　")
        (unless (re-search-forward "[。！？\n]+" nil t)
          (goto-char (point-max)))))))

(defun jieba-rs-backward-sentence (&optional arg)
  "Move point backward ARG Chinese sentences.
Stop at the sentence start, skipping its trailing punctuation."
  (interactive "^p")
  (let ((n (or arg 1)))
    (if (< n 0)
        (jieba-rs-forward-sentence (- n))
      (dotimes (_ n)
        (let ((origin (point)))
          (skip-chars-backward "。！？ \t\n\r\f　")
          (if (re-search-backward "[。！？\n]+" nil t)
              (goto-char (match-end 0))
            (goto-char (point-min)))
          (let ((boundary (point)))
            (skip-chars-forward " \t\r\f　")
            (when (>= (point) origin)
              (goto-char boundary))))))))

;;;###autoload
(defun jieba-rs-toggle-boundaries ()
  "Toggle display of word segmentation boundaries."
  (interactive)
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (if jieba-rs--boundaries-enabled
      (jieba-rs--clear-boundaries)
    (jieba-rs--show-boundaries)))

;;;###autoload
(defun jieba-rs-toggle-tags ()
  "Toggle display of part-of-speech tags."
  (interactive)
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (if jieba-rs--tags-enabled
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

(defun jieba-rs--extract-keywords (beg end top-k)
  "Extract TOP-K keywords from BEG to END using the configured method."
  (unless (featurep 'jieba-rs-module)
    (user-error "Jieba native module not loaded"))
  (let ((k (if (numberp top-k) top-k
             (read-number "Top K: " 10)))
        (text (buffer-substring-no-properties beg end)))
    (if (memq jieba-rs-extract-function '(tfidf textrank))
        (jieba-rs-module-extract-keywords
         text k (symbol-name jieba-rs-extract-function))
      (jieba-rs-module-segment text jieba-rs-hmm))))

;;;###autoload
(defun jieba-rs-extract-keywords-region (start end &optional top-k)
  "Extract TOP-K keywords from region START..END.
In `textrank' mode, uses TextRank keyword extraction.
In `precise' mode, uses word segmentation."
  (interactive "r\nP")
  (let ((items (jieba-rs--extract-keywords start end top-k))
        (title (format "Region %d..%d — %s" start end
                       jieba-rs-extract-function)))
    (jieba-rs--display-extract-results items title)))

;;;###autoload
(defun jieba-rs-extract-keywords-buffer (&optional top-k)
  "Extract TOP-K keywords from the entire buffer."
  (interactive "P")
  (let ((items (jieba-rs--extract-keywords (point-min) (point-max) top-k))
        (title (format "Buffer %s — %s" (buffer-name)
                       jieba-rs-extract-function)))
    (jieba-rs--display-extract-results items title)))

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
  (if (not jieba-rs-mode)
      (jieba-rs--clear-display)
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
