//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Formatter open source project.
//
// Copyright (c) 2018 Apple Inc. and the Swift Formatter project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Formatter project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// A Markdown node that represents block content; that is, content that occupies the full width of
/// the viewport when rendered.
///
/// Examples of block content include paragraphs, block quotes, and code blocks.
///
/// At this time, the `BlockContent` protocol does not add any members of its own over what is
/// already required by `MarkdownNode`. Instead, it is used as a means of enforcing containment
/// relationships between nodes in the AST.
public protocol BlockContent: MarkdownNode {}
