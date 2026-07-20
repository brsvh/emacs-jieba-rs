```
Copyright (C) 2026 Bingshan Chang <chang@bingshan.org>
Permission is granted to copy, distribute and/or modify this document
under the terms of the GNU Free Documentation License, Version 1.3
or any later version published by the Free Software Foundation;
with no Invariant Sections, no Front-Cover Texts, and no Back-Cover Texts.
A copy of the license is included in the section entitled "GNU
Free Documentation License".
```

# emacs-jieba-rs

`emacs-jieba-rs` 为 GNU Emacs 提供由 Rust 动态模块驱动的中文分词功能。其中的 Emacs 软件包 `jieba-rs`
封装了上游同名 Rust 库
[`jieba-rs`](https://github.com/messense/jieba-rs)，支持精确模式、全模式和搜索引擎模式，并提供词性（POS）标注、TF-IDF
与 TextRank 关键词提取、用户词典以及可视词边界。

启用 `jieba-rs-mode` 后，软件包会重映射 GNU Emacs 标准的词句移动命令，使 `M-f`、`M-b`、`M-e` 和 `M-a`
能够按中文词句移动。词边界和词性标签使用覆盖层显示，不会改写缓冲区文本。

## 快速开始

### 要求

- GNU Emacs 30.1 或更高版本，并启用动态模块支持
- 从源码构建时，需要 Rust 1.88 或更高版本（2024 edition）、Cargo、C 编译器和 GNU Make

当前 `Makefile` 按 Linux 动态模块后缀 `.so` 安装模块，flake 直接生成的 per-system 输出也只有
`x86_64-linux`。在其他平台从源码构建时，需要相应调整 `Makefile` 中的模块后缀；flake 的 overlay 不受该
per-system 列表限制。

### 从源码安装

克隆仓库并运行 `make local`：

```sh
git clone https://codeberg.org/bingshan/emacs-jieba-rs.git
cd emacs-jieba-rs
make local
```

`make local` 会以 `release` 模式构建动态模块，将其复制到 `lisp/`，并生成软件包描述与自动加载文件。随后将 `lisp/` 加入
`load-path` 并载入软件包：

```elisp
(add-to-list 'load-path "/path/to/emacs-jieba-rs/lisp")
(require 'jieba-rs)
```

Nix 用户可以直接使用 flake 提供的软件包和 overlay，参见
[Nix 用户指南](#nix-%E7%94%A8%E6%88%B7%E6%8C%87%E5%8D%97)。

### 配置并启用

例如，在所有文本模式中自动启用 `jieba-rs-mode`：

```elisp
(defun my-jieba-rs-mode-enable ()
  "Enable `jieba-rs-mode'."
  (jieba-rs-mode 1))

(add-hook 'text-mode-hook #'my-jieba-rs-mode-enable)
```

也可以在当前缓冲区中执行 `M-x jieba-rs-mode`。所有用户选项和外观均属于 `jieba-rs` 自定义组，可执行
`M-x customize-group RET jieba-rs RET` 进行设置。

### 基本用法

启用次要模式后，可以直接使用 GNU Emacs 原有的 `M-f`、`M-b`、`M-e` 和 `M-a` 按中文词句移动。选中一段文本后执行
`M-x jieba-rs-segment-region` 可以查看分词结果；执行 `M-x jieba-rs-toggle-boundaries` 或
`M-x jieba-rs-toggle-tags` 可以切换可视词边界或词性标签。

## 功能

### 分词算法

`jieba-rs-segment-function` 控制分词命令使用的算法：

| 模式         | 函数                             | 说明                                       |
| ------------ | -------------------------------- | ------------------------------------------ |
| 精确模式     | `jieba-rs-module-segment`        | 默认模式，支持 HMM 新词发现                |
| 全模式       | `jieba-rs-module-segment-all`    | 扫描所有可能的切分，不使用 HMM             |
| 搜索引擎模式 | `jieba-rs-module-segment-search` | 产生适合建立搜索索引的细粒度切分，支持 HMM |

例如，改用搜索引擎模式：

```elisp
(setq jieba-rs-segment-function #'jieba-rs-module-segment-search)
```

区域分词会在结果缓冲区中显示切分结果；在支持工具提示的图形会话中启用 `tooltip-mode` 时，还会在区域开头显示工具提示。缓冲区分词会遵守窄化范围。

### 词边界与词性标签

`jieba-rs-toggle-boundaries` 使用覆盖层在词之间显示
`jieba-rs-boundary-separator`，`jieba-rs-toggle-tags` 则在词后显示词性标签。两种显示都不会改写缓冲区文本。

软件包只为当前窗口的可见范围创建覆盖层，并在编辑、滚动或重新居中后刷新。词性显示会将常见的 ICTCLAS 词性代码映射为小写类别，例如
`noun`、`verb` 和 `adj`；没有映射的代码保持不变。

### 关键词提取

`jieba-rs-extract-function` 控制关键词提取方式：

| 值         | 说明                           |
| ---------- | ------------------------------ |
| `tfidf`    | 使用 TF-IDF 提取关键词，默认值 |
| `textrank` | 使用 TextRank 提取关键词       |
| `precise`  | 返回精确模式的分词结果         |

区域和缓冲区命令在没有数值前缀参数时会询问 Top K，默认值为 `10`；数值前缀参数会直接作为 Top K。TF-IDF 和 TextRank
使用该值限制结果数量。缓冲区命令会遵守窄化范围。

### 中文词句移动

`jieba-rs-mode` 通过命令重映射替换标准词句移动命令，因此原命令的自定义键位也会自动沿用：

| 标准命令            | `jieba-rs` 命令              | 默认键位 |
| ------------------- | ---------------------------- | -------- |
| `forward-word`      | `jieba-rs-forward-word`      | `M-f`    |
| `backward-word`     | `jieba-rs-backward-word`     | `M-b`    |
| `forward-sentence`  | `jieba-rs-forward-sentence`  | `M-e`    |
| `backward-sentence` | `jieba-rs-backward-sentence` | `M-a`    |

词移动始终使用精确模式，并遵守 `jieba-rs-hmm`。句移动将中文句号、问号、感叹号和换行，即 `[。！？\n]+`，视为句子分隔符。

### 用户词典

`jieba-rs-user-dict` 指定用户词典文件，默认值为：

```elisp
(expand-file-name "jieba-rs/user.dict" user-emacs-directory)
```

将该选项设为 `nil` 可以禁用自动加载。词典使用 `jieba-rs` 的标准格式，每行依次包含词语、词频和可选词性标签，并以空格分隔：

```text
星际争霸 100 nz
量子计算机 200
```

启用 `jieba-rs-mode` 时，如果文件存在，软件包会将其载入原生模块。执行 `M-x jieba-rs-add-word` 可以在当前 Emacs
会话中添加词语；带前缀参数执行 `C-u M-x jieba-rs-add-word`，还会将新词追加到用户词典文件。

## 命令

| 命令                               | 说明                                         |
| ---------------------------------- | -------------------------------------------- |
| `jieba-rs-mode`                    | 在当前缓冲区中启用或禁用次要模式             |
| `jieba-rs-segment-region`          | 对活动区域分词并显示结果                     |
| `jieba-rs-segment-buffer`          | 对当前可访问范围分词并显示结果               |
| `jieba-rs-toggle-boundaries`       | 切换可视词边界                               |
| `jieba-rs-toggle-tags`             | 切换可视词性标签                             |
| `jieba-rs-add-word`                | 向词典添加词语；前缀参数同时持久化到用户词典 |
| `jieba-rs-extract-keywords-region` | 从活动区域提取关键词                         |
| `jieba-rs-extract-keywords-buffer` | 从当前可访问范围提取关键词                   |
| `jieba-rs-forward-word`            | 向前移动指定数量的中文词                     |
| `jieba-rs-backward-word`           | 向后移动指定数量的中文词                     |
| `jieba-rs-forward-sentence`        | 向前移动指定数量的中文句                     |
| `jieba-rs-backward-sentence`       | 向后移动指定数量的中文句                     |

## 自定义选项

| 选项                          | 默认值                                                         | 用途                         |
| ----------------------------- | -------------------------------------------------------------- | ---------------------------- |
| `jieba-rs-hmm`                | `t`                                                            | 是否启用 HMM 新词发现        |
| `jieba-rs-user-dict`          | `(expand-file-name "jieba-rs/user.dict" user-emacs-directory)` | 用户词典路径；`nil` 表示禁用 |
| `jieba-rs-segment-function`   | `jieba-rs-module-segment`                                      | 分词算法                     |
| `jieba-rs-normalize-rules`    | 内置控制字符和空白规则                                         | 覆盖层分词前的文本规范化规则 |
| `jieba-rs-extract-function`   | `tfidf`                                                        | 关键词提取算法               |
| `jieba-rs-boundary-separator` | `"  "`                                                         | 可视词边界使用的分隔字符串   |

### 外观

| 外观                     | 默认样式                                 | 用途       |
| ------------------------ | ---------------------------------------- | ---------- |
| `jieba-rs-boundary-face` | 继承 `shadow`                            | 可视词边界 |
| `jieba-rs-tag-face`      | 继承 `font-lock-keyword-face` 并使用斜体 | 词性标签   |

## 行为与注意事项

- `jieba-rs-normalize-rules` 只用于覆盖层分词，不会修改缓冲区内容。为保持字符位置一致，每条规则的替换字符串必须恰好是一个普通空格。
- 原生模块中的 Jieba 实例属于当前 Emacs 进程。载入用户词典或通过 `jieba-rs-add-word`
  添加的词语会影响所有缓冲区；禁用次要模式或将 `jieba-rs-user-dict` 设为 `nil` 不会撤销已经载入的词语。
- `jieba-rs-segment-buffer` 和 `jieba-rs-extract-keywords-buffer` 都会遵守窄化范围。
- 中文词移动和可视覆盖层固定使用精确模式；改变 `jieba-rs-segment-function` 只会影响区域与缓冲区分词命令。

## 开发与测试

Emacs Lisp 代码位于 `lisp/`，Rust 源码位于 `src/`，集成测试位于 `tests/`。仓库根目录的 `Makefile`
提供以下常用目标：

| 目标                         | 用途                                            |
| ---------------------------- | ----------------------------------------------- |
| `make`、`make module`        | 以 `release` 模式构建原生模块并复制到 `lisp/`   |
| `make local`                 | 构建模块，并生成软件包描述与自动加载文件        |
| `make autoloads`             | 生成 `lisp/jieba-rs-autoloads.el`               |
| `make pkg`                   | 生成 `lisp/jieba-rs-pkg.el`                     |
| `make test`                  | 构建模块并运行 ERT 测试                         |
| `make check`                 | 构建模块，再运行 Cargo 和 ERT 测试              |
| `make release-version`       | 校验并输出 Emacs 包与 Rust crate 的共同版本     |
| `make release-archive`       | 生成 `dist/jieba-rs-VERSION.tar` 发布归档       |
| `make check-release-archive` | 校验归档内容，并隔离安装后执行分词              |
| `make release-artifact`      | 输出当前发布归档的路径                          |
| `make clean`                 | 删除 `lisp/` 生成文件和 `dist/`，保留 `target/` |

运行完整检查：

```sh
make check
```

`release-archive` 生成一个标准 Emacs 包归档，其中同时包含 `jieba-rs-module.so`。Rust
模块不作为独立软件包发布，并与 Emacs 包使用同一版本号。 当前 GitHub 发布归档使用 Rust 1.88.0 在 Ubuntu 24.04
上构建，目标为 `x86_64-unknown-linux-gnu`。

`nix develop` 提供仓库使用的格式化和维护工具，但不是包含 Rust、C 编译器和 GNU Emacs 的完整源码构建环境。

## Nix 用户指南

flake 提供 overlay、Emacs 包与 Rust 模块输出、带有 `jieba-rs` 的 GNU Emacs 启动器，以及 ERT、byte
compilation 和 Checkdoc 检查器。 当前直接生成的软件包、开发环境和启动器仅有 `x86_64-linux` 输出；overlay
本身不受这一 per-system 列表限制。

### 在 NixOS 中使用 overlay

下面的 flake 示例将 overlay 应用于 `emacsPackagesFor`，再把包含 `jieba-rs` 的 `emacs-pgtk`
加入系统软件包：

```nix
{
  inputs = {
    emacs-jieba-rs = {
      url = "git+https://codeberg.org/bingshan/emacs-jieba-rs.git";
    };

    nixpkgs = {
      url = "git+https://github.com/NixOS/nixpkgs.git?ref=nixos-unstable";
    };
  };

  outputs =
    {
      emacs-jieba-rs,
      nixpkgs,
      ...
    }:
    {
      nixosConfigurations = {
        HOSTNAME =
          nixpkgs.lib.nixosSystem
            {
              modules = [
                (
                  { pkgs, ... }:
                  let
                    emacs =
                      (pkgs.emacsPackagesFor pkgs.emacs-pgtk).emacsWithPackages
                        (
                          epkgs: [
                            epkgs.jieba-rs
                          ]
                        );
                  in
                  {
                    environment = {
                      systemPackages = [
                        emacs
                      ];
                    };

                    nixpkgs = {
                      overlays = [
                        emacs-jieba-rs.overlays.default
                      ];
                    };
                  }
                )
              ];
              system = "x86_64-linux";
            };
      };
    };
}
```

### 使用 flake 输出

| 输出                            | 用途                                      |
| ------------------------------- | ----------------------------------------- |
| `jieba-rs`                      | 构建包含 Rust 模块的 Emacs 包             |
| `jieba-rs-module`               | 构建 Rust 动态模块并运行 Cargo 测试       |
| `emacs30-with-jieba-rs`         | 在全新的独立初始化目录中启动 GNU Emacs 30 |
| `emacs31-with-jieba-rs`         | 在全新的独立初始化目录中启动 GNU Emacs 31 |
| `emacs30-run-jieba-rs-tests`    | 使用 GNU Emacs 30 运行 ERT 测试           |
| `emacs31-run-jieba-rs-tests`    | 使用 GNU Emacs 31 运行 ERT 测试           |
| `emacs30-byte-compile-jieba-rs` | 使用 GNU Emacs 30 编译并加载验证软件包    |
| `emacs31-byte-compile-jieba-rs` | 使用 GNU Emacs 31 编译并加载验证软件包    |
| `emacs30-checkdoc-jieba-rs`     | 使用 GNU Emacs 30 运行 Checkdoc           |
| `emacs31-checkdoc-jieba-rs`     | 使用 GNU Emacs 31 运行 Checkdoc           |

例如，构建并启动 GNU Emacs 31，再使用同一版本运行测试：

```sh
nix build .#emacs31-with-jieba-rs
nix run .#emacs31-with-jieba-rs
nix run .#emacs31-run-jieba-rs-tests
```

对测试启动器执行 `nix build` 会构建启动器及其依赖，但不会执行启动器中的 ERT 命令；要运行 ERT 测试，请使用 `nix run`。

## 相关项目

- [`jieba-rs`](https://github.com/messense/jieba-rs)：本项目使用的 Rust 中文分词库
- [`emacs-jieba`](https://github.com/kisaragi-hiu/emacs-jieba)：另一种 GNU Emacs
  Jieba 集成

## AI 辅助声明

本项目中的所有代码、测试和文档均在 AI 工具的辅助下开发。所有 AI 生成的内容均经过维护者审查，并在必要时进行了修改。维护者对最终内容负全部责任。未向 AI
工具有意提供任何机密信息、用户隐私数据或其他敏感信息。

## 项目许可证

`emacs-jieba-rs` 是自由软件，遵循
[GNU General Public License](https://www.gnu.org/licenses/gpl-3.0.html) 第 3 版
或更高版本。完整许可证文本见 [`COPYING`](../COPYING)。

## GNU Free Documentation License

本文档遵循 GNU Free Documentation License 第 1.3 版或更高版本。

<details>
<summary>展开许可证全文</summary>

```text

                GNU Free Documentation License
                 Version 1.3, 3 November 2008


 Copyright (C) 2000, 2001, 2002, 2007, 2008 Free Software Foundation, Inc.
     <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

 0. PREAMBLE

 The purpose of this License is to make a manual, textbook, or other
 functional and useful document "free" in the sense of freedom: to
 assure everyone the effective freedom to copy and redistribute it,
 with or without modifying it, either commercially or noncommercially.
 Secondarily, this License preserves for the author and publisher a way
 to get credit for their work, while not being considered responsible
 for modifications made by others.

 This License is a kind of "copyleft", which means that derivative
 works of the document must themselves be free in the same sense.  It
 complements the GNU General Public License, which is a copyleft
 license designed for free software.

 We have designed this License in order to use it for manuals for free
 software, because free software needs free documentation: a free
 program should come with manuals providing the same freedoms that the
 software does.  But this License is not limited to software manuals;
 it can be used for any textual work, regardless of subject matter or
 whether it is published as a printed book.  We recommend this License
 principally for works whose purpose is instruction or reference.


 1. APPLICABILITY AND DEFINITIONS

 This License applies to any manual or other work, in any medium, that
 contains a notice placed by the copyright holder saying it can be
 distributed under the terms of this License.  Such a notice grants a
 world-wide, royalty-free license, unlimited in duration, to use that
 work under the conditions stated herein.  The "Document", below,
 refers to any such manual or work.  Any member of the public is a
 licensee, and is addressed as "you".  You accept the license if you
 copy, modify or distribute the work in a way requiring permission
 under copyright law.

 A "Modified Version" of the Document means any work containing the
 Document or a portion of it, either copied verbatim, or with
 modifications and/or translated into another language.

 A "Secondary Section" is a named appendix or a front-matter section of
 the Document that deals exclusively with the relationship of the
 publishers or authors of the Document to the Document's overall
 subject (or to related matters) and contains nothing that could fall
 directly within that overall subject.  (Thus, if the Document is in
 part a textbook of mathematics, a Secondary Section may not explain
 any mathematics.)  The relationship could be a matter of historical
 connection with the subject or with related matters, or of legal,
 commercial, philosophical, ethical or political position regarding
 them.

 The "Invariant Sections" are certain Secondary Sections whose titles
 are designated, as being those of Invariant Sections, in the notice
 that says that the Document is released under this License.  If a
 section does not fit the above definition of Secondary then it is not
 allowed to be designated as Invariant.  The Document may contain zero
 Invariant Sections.  If the Document does not identify any Invariant
 Sections then there are none.

 The "Cover Texts" are certain short passages of text that are listed,
 as Front-Cover Texts or Back-Cover Texts, in the notice that says that
 the Document is released under this License.  A Front-Cover Text may
 be at most 5 words, and a Back-Cover Text may be at most 25 words.

 A "Transparent" copy of the Document means a machine-readable copy,
 represented in a format whose specification is available to the
 general public, that is suitable for revising the document
 straightforwardly with generic text editors or (for images composed of
 pixels) generic paint programs or (for drawings) some widely available
 drawing editor, and that is suitable for input to text formatters or
 for automatic translation to a variety of formats suitable for input
 to text formatters.  A copy made in an otherwise Transparent file
 format whose markup, or absence of markup, has been arranged to thwart
 or discourage subsequent modification by readers is not Transparent.
 An image format is not Transparent if used for any substantial amount
 of text.  A copy that is not "Transparent" is called "Opaque".

 Examples of suitable formats for Transparent copies include plain
 ASCII without markup, Texinfo input format, LaTeX input format, SGML
 or XML using a publicly available DTD, and standard-conforming simple
 HTML, PostScript or PDF designed for human modification.  Examples of
 transparent image formats include PNG, XCF and JPG.  Opaque formats
 include proprietary formats that can be read and edited only by
 proprietary word processors, SGML or XML for which the DTD and/or
 processing tools are not generally available, and the
 machine-generated HTML, PostScript or PDF produced by some word
 processors for output purposes only.

 The "Title Page" means, for a printed book, the title page itself,
 plus such following pages as are needed to hold, legibly, the material
 this License requires to appear in the title page.  For works in
 formats which do not have any title page as such, "Title Page" means
 the text near the most prominent appearance of the work's title,
 preceding the beginning of the body of the text.

 The "publisher" means any person or entity that distributes copies of
 the Document to the public.

 A section "Entitled XYZ" means a named subunit of the Document whose
 title either is precisely XYZ or contains XYZ in parentheses following
 text that translates XYZ in another language.  (Here XYZ stands for a
 specific section name mentioned below, such as "Acknowledgements",
 "Dedications", "Endorsements", or "History".)  To "Preserve the Title"
 of such a section when you modify the Document means that it remains a
 section "Entitled XYZ" according to this definition.

 The Document may include Warranty Disclaimers next to the notice which
 states that this License applies to the Document.  These Warranty
 Disclaimers are considered to be included by reference in this
 License, but only as regards disclaiming warranties: any other
 implication that these Warranty Disclaimers may have is void and has
 no effect on the meaning of this License.

 2. VERBATIM COPYING

 You may copy and distribute the Document in any medium, either
 commercially or noncommercially, provided that this License, the
 copyright notices, and the license notice saying this License applies
 to the Document are reproduced in all copies, and that you add no
 other conditions whatsoever to those of this License.  You may not use
 technical measures to obstruct or control the reading or further
 copying of the copies you make or distribute.  However, you may accept
 compensation in exchange for copies.  If you distribute a large enough
 number of copies you must also follow the conditions in section 3.

 You may also lend copies, under the same conditions stated above, and
 you may publicly display copies.


 3. COPYING IN QUANTITY

 If you publish printed copies (or copies in media that commonly have
 printed covers) of the Document, numbering more than 100, and the
 Document's license notice requires Cover Texts, you must enclose the
 copies in covers that carry, clearly and legibly, all these Cover
 Texts: Front-Cover Texts on the front cover, and Back-Cover Texts on
 the back cover.  Both covers must also clearly and legibly identify
 you as the publisher of these copies.  The front cover must present
 the full title with all words of the title equally prominent and
 visible.  You may add other material on the covers in addition.
 Copying with changes limited to the covers, as long as they preserve
 the title of the Document and satisfy these conditions, can be treated
 as verbatim copying in other respects.

 If the required texts for either cover are too voluminous to fit
 legibly, you should put the first ones listed (as many as fit
 reasonably) on the actual cover, and continue the rest onto adjacent
 pages.

 If you publish or distribute Opaque copies of the Document numbering
 more than 100, you must either include a machine-readable Transparent
 copy along with each Opaque copy, or state in or with each Opaque copy
 a computer-network location from which the general network-using
 public has access to download using public-standard network protocols
 a complete Transparent copy of the Document, free of added material.
 If you use the latter option, you must take reasonably prudent steps,
 when you begin distribution of Opaque copies in quantity, to ensure
 that this Transparent copy will remain thus accessible at the stated
 location until at least one year after the last time you distribute an
 Opaque copy (directly or through your agents or retailers) of that
 edition to the public.

 It is requested, but not required, that you contact the authors of the
 Document well before redistributing any large number of copies, to
 give them a chance to provide you with an updated version of the
 Document.


 4. MODIFICATIONS

 You may copy and distribute a Modified Version of the Document under
 the conditions of sections 2 and 3 above, provided that you release
 the Modified Version under precisely this License, with the Modified
 Version filling the role of the Document, thus licensing distribution
 and modification of the Modified Version to whoever possesses a copy
 of it.  In addition, you must do these things in the Modified Version:

 A. Use in the Title Page (and on the covers, if any) a title distinct
    from that of the Document, and from those of previous versions
    (which should, if there were any, be listed in the History section
    of the Document).  You may use the same title as a previous version
    if the original publisher of that version gives permission.
 B. List on the Title Page, as authors, one or more persons or entities
    responsible for authorship of the modifications in the Modified
    Version, together with at least five of the principal authors of the
    Document (all of its principal authors, if it has fewer than five),
    unless they release you from this requirement.
 C. State on the Title page the name of the publisher of the
    Modified Version, as the publisher.
 D. Preserve all the copyright notices of the Document.
 E. Add an appropriate copyright notice for your modifications
    adjacent to the other copyright notices.
 F. Include, immediately after the copyright notices, a license notice
    giving the public permission to use the Modified Version under the
    terms of this License, in the form shown in the Addendum below.
 G. Preserve in that license notice the full lists of Invariant Sections
    and required Cover Texts given in the Document's license notice.
 H. Include an unaltered copy of this License.
 I. Preserve the section Entitled "History", Preserve its Title, and add
    to it an item stating at least the title, year, new authors, and
    publisher of the Modified Version as given on the Title Page.  If
    there is no section Entitled "History" in the Document, create one
    stating the title, year, authors, and publisher of the Document as
    given on its Title Page, then add an item describing the Modified
    Version as stated in the previous sentence.
 J. Preserve the network location, if any, given in the Document for
    public access to a Transparent copy of the Document, and likewise
    the network locations given in the Document for previous versions
    it was based on.  These may be placed in the "History" section.
    You may omit a network location for a work that was published at
    least four years before the Document itself, or if the original
    publisher of the version it refers to gives permission.
 K. For any section Entitled "Acknowledgements" or "Dedications",
    Preserve the Title of the section, and preserve in the section all
    the substance and tone of each of the contributor acknowledgements
    and/or dedications given therein.
 L. Preserve all the Invariant Sections of the Document,
    unaltered in their text and in their titles.  Section numbers
    or the equivalent are not considered part of the section titles.
 M. Delete any section Entitled "Endorsements".  Such a section
    may not be included in the Modified Version.
 N. Do not retitle any existing section to be Entitled "Endorsements"
    or to conflict in title with any Invariant Section.
 O. Preserve any Warranty Disclaimers.

 If the Modified Version includes new front-matter sections or
 appendices that qualify as Secondary Sections and contain no material
 copied from the Document, you may at your option designate some or all
 of these sections as invariant.  To do this, add their titles to the
 list of Invariant Sections in the Modified Version's license notice.
 These titles must be distinct from any other section titles.

 You may add a section Entitled "Endorsements", provided it contains
 nothing but endorsements of your Modified Version by various
 parties--for example, statements of peer review or that the text has
 been approved by an organization as the authoritative definition of a
 standard.

 You may add a passage of up to five words as a Front-Cover Text, and a
 passage of up to 25 words as a Back-Cover Text, to the end of the list
 of Cover Texts in the Modified Version.  Only one passage of
 Front-Cover Text and one of Back-Cover Text may be added by (or
 through arrangements made by) any one entity.  If the Document already
 includes a cover text for the same cover, previously added by you or
 by arrangement made by the same entity you are acting on behalf of,
 you may not add another; but you may replace the old one, on explicit
 permission from the previous publisher that added the old one.

 The author(s) and publisher(s) of the Document do not by this License
 give permission to use their names for publicity for or to assert or
 imply endorsement of any Modified Version.


 5. COMBINING DOCUMENTS

 You may combine the Document with other documents released under this
 License, under the terms defined in section 4 above for modified
 versions, provided that you include in the combination all of the
 Invariant Sections of all of the original documents, unmodified, and
 list them all as Invariant Sections of your combined work in its
 license notice, and that you preserve all their Warranty Disclaimers.

 The combined work need only contain one copy of this License, and
 multiple identical Invariant Sections may be replaced with a single
 copy.  If there are multiple Invariant Sections with the same name but
 different contents, make the title of each such section unique by
 adding at the end of it, in parentheses, the name of the original
 author or publisher of that section if known, or else a unique number.
 Make the same adjustment to the section titles in the list of
 Invariant Sections in the license notice of the combined work.

 In the combination, you must combine any sections Entitled "History"
 in the various original documents, forming one section Entitled
 "History"; likewise combine any sections Entitled "Acknowledgements",
 and any sections Entitled "Dedications".  You must delete all sections
 Entitled "Endorsements".


 6. COLLECTIONS OF DOCUMENTS

 You may make a collection consisting of the Document and other
 documents released under this License, and replace the individual
 copies of this License in the various documents with a single copy
 that is included in the collection, provided that you follow the rules
 of this License for verbatim copying of each of the documents in all
 other respects.

 You may extract a single document from such a collection, and
 distribute it individually under this License, provided you insert a
 copy of this License into the extracted document, and follow this
 License in all other respects regarding verbatim copying of that
 document.


 7. AGGREGATION WITH INDEPENDENT WORKS

 A compilation of the Document or its derivatives with other separate
 and independent documents or works, in or on a volume of a storage or
 distribution medium, is called an "aggregate" if the copyright
 resulting from the compilation is not used to limit the legal rights
 of the compilation's users beyond what the individual works permit.
 When the Document is included in an aggregate, this License does not
 apply to the other works in the aggregate which are not themselves
 derivative works of the Document.

 If the Cover Text requirement of section 3 is applicable to these
 copies of the Document, then if the Document is less than one half of
 the entire aggregate, the Document's Cover Texts may be placed on
 covers that bracket the Document within the aggregate, or the
 electronic equivalent of covers if the Document is in electronic form.
 Otherwise they must appear on printed covers that bracket the whole
 aggregate.


 8. TRANSLATION

 Translation is considered a kind of modification, so you may
 distribute translations of the Document under the terms of section 4.
 Replacing Invariant Sections with translations requires special
 permission from their copyright holders, but you may include
 translations of some or all Invariant Sections in addition to the
 original versions of these Invariant Sections.  You may include a
 translation of this License, and all the license notices in the
 Document, and any Warranty Disclaimers, provided that you also include
 the original English version of this License and the original versions
 of those notices and disclaimers.  In case of a disagreement between
 the translation and the original version of this License or a notice
 or disclaimer, the original version will prevail.

 If a section in the Document is Entitled "Acknowledgements",
 "Dedications", or "History", the requirement (section 4) to Preserve
 its Title (section 1) will typically require changing the actual
 title.


 9. TERMINATION

 You may not copy, modify, sublicense, or distribute the Document
 except as expressly provided under this License.  Any attempt
 otherwise to copy, modify, sublicense, or distribute it is void, and
 will automatically terminate your rights under this License.

 However, if you cease all violation of this License, then your license
 from a particular copyright holder is reinstated (a) provisionally,
 unless and until the copyright holder explicitly and finally
 terminates your license, and (b) permanently, if the copyright holder
 fails to notify you of the violation by some reasonable means prior to
 60 days after the cessation.

 Moreover, your license from a particular copyright holder is
 reinstated permanently if the copyright holder notifies you of the
 violation by some reasonable means, this is the first time you have
 received notice of violation of this License (for any work) from that
 copyright holder, and you cure the violation prior to 30 days after
 your receipt of the notice.

 Termination of your rights under this section does not terminate the
 licenses of parties who have received copies or rights from you under
 this License.  If your rights have been terminated and not permanently
 reinstated, receipt of a copy of some or all of the same material does
 not give you any rights to use it.


 10. FUTURE REVISIONS OF THIS LICENSE

 The Free Software Foundation may publish new, revised versions of the
 GNU Free Documentation License from time to time.  Such new versions
 will be similar in spirit to the present version, but may differ in
 detail to address new problems or concerns.  See
 https://www.gnu.org/licenses/.

 Each version of the License is given a distinguishing version number.
 If the Document specifies that a particular numbered version of this
 License "or any later version" applies to it, you have the option of
 following the terms and conditions either of that specified version or
 of any later version that has been published (not as a draft) by the
 Free Software Foundation.  If the Document does not specify a version
 number of this License, you may choose any version ever published (not
 as a draft) by the Free Software Foundation.  If the Document
 specifies that a proxy can decide which future versions of this
 License can be used, that proxy's public statement of acceptance of a
 version permanently authorizes you to choose that version for the
 Document.

 11. RELICENSING

 "Massive Multiauthor Collaboration Site" (or "MMC Site") means any
 World Wide Web server that publishes copyrightable works and also
 provides prominent facilities for anybody to edit those works.  A
 public wiki that anybody can edit is an example of such a server.  A
 "Massive Multiauthor Collaboration" (or "MMC") contained in the site
 means any set of copyrightable works thus published on the MMC site.

 "CC-BY-SA" means the Creative Commons Attribution-Share Alike 3.0
 license published by Creative Commons Corporation, a not-for-profit
 corporation with a principal place of business in San Francisco,
 California, as well as future copyleft versions of that license
 published by that same organization.

 "Incorporate" means to publish or republish a Document, in whole or in
 part, as part of another Document.

 An MMC is "eligible for relicensing" if it is licensed under this
 License, and if all works that were first published under this License
 somewhere other than this MMC, and subsequently incorporated in whole or
 in part into the MMC, (1) had no cover texts or invariant sections, and
 (2) were thus incorporated prior to November 1, 2008.

 The operator of an MMC Site may republish an MMC contained in the site
 under CC-BY-SA on the same site at any time before August 1, 2009,
 provided the MMC is eligible for relicensing.


 ADDENDUM: How to use this License for your documents

 To use this License in a document you have written, include a copy of
 the License in the document and put the following copyright and
 license notices just after the title page:

     Copyright (c)  YEAR  YOUR NAME.
     Permission is granted to copy, distribute and/or modify this document
     under the terms of the GNU Free Documentation License, Version 1.3
     or any later version published by the Free Software Foundation;
     with no Invariant Sections, no Front-Cover Texts, and no Back-Cover Texts.
     A copy of the license is included in the section entitled "GNU
     Free Documentation License".

 If you have Invariant Sections, Front-Cover Texts and Back-Cover Texts,
 replace the "with...Texts." line with this:

     with the Invariant Sections being LIST THEIR TITLES, with the
     Front-Cover Texts being LIST, and with the Back-Cover Texts being LIST.

 If you have Invariant Sections without Cover Texts, or some other
 combination of the three, merge those two alternatives to suit the
 situation.

 If your document contains nontrivial examples of program code, we
 recommend releasing these examples in parallel under your choice of
 free software license, such as the GNU General Public License,
 to permit their use in free software.

```

</details>
