//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftFormatConfiguration
import SwiftFormatCore
import SwiftSyntax

private let rangeOperators: Set = ["...", "..<"]

private final class TokenStreamCreator: SyntaxVisitor {
  private var tokens = [Token]()
  private var beforeMap = [TokenSyntax: [Token]]()
  private var afterMap = [TokenSyntax: [[Token]]]()
  private let config: Configuration
  private let maxlinelength: Int

  init(configuration: Configuration) {
    self.config = configuration
    self.maxlinelength = config.lineLength
  }

  func makeStream(from node: Syntax) -> [Token] {
    visit(node)
    defer { tokens = [] }
    return tokens
  }

  var openings = 0

  func before(_ token: TokenSyntax?, tokens: Token...) {
    guard let tok = token else { return }
    for preToken in tokens {
      if case .open = preToken {
        openings += 1
      } else if case .close = preToken {
        assert(openings > 0)
        openings -= 1
      }
    }
    beforeMap[tok, default: []] += tokens
  }

  func after(_ token: TokenSyntax?, tokens: Token...) {
    guard let tok = token else { return }
    for postToken in tokens {
      if case .open = postToken {
        openings += 1
      } else if case .close = postToken {
        assert(openings > 0)
        openings -= 1
      }
    }
    afterMap[tok, default: []].append(tokens)
  }

  private func insertToken<Node: Collection>(
    _ token: Token,
    betweenChildrenOf collectionNode: Node
  ) where Node.Element: Syntax, Node.Index == Int {
    if collectionNode.count > 0 {
      for i in 0..<(collectionNode.count - 1) {
        after(collectionNode[i].lastToken, tokens: token)
      }
    }
  }

  private func verbatimToken(_ node: Syntax) {
    if let firstToken = node.firstToken, let before = beforeMap[firstToken] {
      tokens += before
    }
    appendToken(.verbatim(Verbatim(text: node.description)))
    if let lastToken = node.lastToken, let afterGroups = afterMap[lastToken] {
      for after in afterGroups.reversed() {
        tokens += after
      }
    }
  }

  override func visitPre(_ node: Syntax) {}

  // MARK: - Type declaration nodes

  override func visit(_ node: ClassDeclSyntax) {
    arrangeTypeDeclBlock(
      node,
      attributes: node.attributes,
      typeKeyword: node.classKeyword,
      members: node.members,
      genericWhereClause: node.genericWhereClause)
    super.visit(node)
  }

  override func visit(_ node: StructDeclSyntax) {
    arrangeTypeDeclBlock(
      node,
      attributes: node.attributes,
      typeKeyword: node.structKeyword,
      members: node.members,
      genericWhereClause: node.genericWhereClause)
    super.visit(node)
  }

  override func visit(_ node: EnumDeclSyntax) {
    arrangeTypeDeclBlock(
      node,
      attributes: node.attributes,
      typeKeyword: node.enumKeyword,
      members: node.members,
      genericWhereClause: node.genericWhereClause)
    super.visit(node)
  }

  override func visit(_ node: ProtocolDeclSyntax) {
    arrangeTypeDeclBlock(
      node,
      attributes: node.attributes,
      typeKeyword: node.protocolKeyword,
      members: node.members,
      genericWhereClause: node.genericWhereClause)
    super.visit(node)
  }

  override func visit(_ node: ExtensionDeclSyntax) {
    arrangeTypeDeclBlock(
      node,
      attributes: node.attributes,
      typeKeyword: node.extensionKeyword,
      members: node.members,
      genericWhereClause: node.genericWhereClause)
    super.visit(node)
  }

  /// Applies formatting tokens to the tokens in the given type declaration node (i.e., a class,
  /// struct, enum, protocol, or extension).
  private func arrangeTypeDeclBlock(
    _ node: Syntax,
    attributes: AttributeListSyntax?,
    typeKeyword: TokenSyntax,
    members: MemberDeclBlockSyntax,
    genericWhereClause: GenericWhereClauseSyntax?
  ) {
    // TODO(allevato): If `EnumDeclSyntax` is updated to extend `DeclGroupSyntax` (I can't see a
    // reason that it shouldn't), then we can simplify this function's signature by constraining
    // `node` to that protocol and removing the explicit `attributes` and `members` arguments.

    if let attributes = attributes {
      before(node.firstToken, tokens: .space(size: 0), .open(.consistent, 0))
      after(attributes.lastToken, tokens: .open)
    } else {
      before(node.firstToken, tokens: .space(size: 0), .open(.consistent, 0), .open)
    }

    after(typeKeyword, tokens: .break)

    if let genericWhereClause = genericWhereClause {
      before(
        genericWhereClause.firstToken,
        tokens: .break, .open(.inconsistent, 0), .break(size: 0), .open(.consistent, 0)
      )
      after(genericWhereClause.lastToken, tokens: .break, .close, .close)
    } else {
      before(members.leftBrace, tokens: .break)
    }

    // The body may be free of other syntax nodes, but we still need to insert the breaks if it
    // contains a comment (which will be in the leading trivia of the right brace).
    let commentPrecedesRightBrace = members.rightBrace.leadingTrivia.numberOfComments > 0
    let isBodyCompletelyEmpty = members.members.isEmpty && !commentPrecedesRightBrace

    if !isBodyCompletelyEmpty {
      after(members.leftBrace, tokens: .close, .close, .break(offset: 2), .open(.consistent, 0))
      before(members.rightBrace, tokens: .break(offset: -2), .close)
    } else {
      // The size-0 break in the empty case allows for a break between the braces in the rare event
      // that the declaration would be exactly the column limit + 1.
      after(members.leftBrace, tokens: .close, .close, .break(size: 0))
    }
  }

  // MARK: - Function and function-like declaration nodes (initializers, deinitializers, subscripts)

  override func visit(_ node: FunctionDeclSyntax) {
    if case .spacedBinaryOperator = node.identifier.tokenKind {
      after(node.identifier.lastToken, tokens: .space)
    }
    arrangeFunctionLikeDecl(
      node,
      attributes: node.attributes,
      genericWhereClause: node.genericWhereClause,
      body: node.body,
      bodyContentsAreEmpty: node.body?.statements.isEmpty ?? true)

    after(node.funcKeyword, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: InitializerDeclSyntax) {
    arrangeFunctionLikeDecl(
      node,
      attributes: node.attributes,
      genericWhereClause: node.genericWhereClause,
      body: node.body,
      bodyContentsAreEmpty: node.body?.statements.isEmpty ?? true)

    before(node.throwsOrRethrowsKeyword, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: DeinitializerDeclSyntax) {
    arrangeFunctionLikeDecl(
      node,
      attributes: node.attributes,
      genericWhereClause: nil,
      body: node.body,
      bodyContentsAreEmpty: node.body.statements.isEmpty)
    super.visit(node)
  }

  override func visit(_ node: SubscriptDeclSyntax) {
    arrangeFunctionLikeDecl(
      node,
      attributes: node.attributes,
      genericWhereClause: node.genericWhereClause,
      body: node.accessor,
      bodyContentsAreEmpty: isBodyEmpty(node.accessor))

    before(node.result.firstToken, tokens: .break)
    super.visit(node)
  }

  /// Applies formatting tokens to the tokens in the given function or function-like declaration
  /// node (e.g., initializers, deinitiailizers, and subscripts).
  private func arrangeFunctionLikeDecl(
    _ node: Syntax,
    attributes: AttributeListSyntax?,
    genericWhereClause: GenericWhereClauseSyntax?,
    body: BracedSyntax?,
    bodyContentsAreEmpty: Bool
  ) {
    before(node.firstToken, tokens: .open(.inconsistent, 0))
    
    if let attributes = attributes {
      before(node.firstToken, tokens: .space(size: 0), .open(.consistent, 0))
      after(attributes.lastToken, tokens: .open)
    } else {
      before(node.firstToken, tokens: .space(size: 0), .open(.consistent, 0), .open)
    }

    if let genericWhereClause = genericWhereClause {
      before(
        genericWhereClause.firstToken,
        tokens: .break, .open(.inconsistent, 0), .break(size: 0), .open(.consistent, 0)
      )
      if body?.leftBrace != nil {
        after(genericWhereClause.lastToken, tokens: .break, .close, .close)
      } else {
        after(genericWhereClause.lastToken, tokens: .close, .close)
      }
    } else {
      before(body?.leftBrace, tokens: .break)
    }

    if let body = body {
      // The body may be free of other syntax nodes, but we still need to insert the breaks if it
      // contains a comment (which will be in the leading trivia of the right brace).
      let commentPrecedesRightBrace = body.rightBrace.leadingTrivia.numberOfComments > 0
      let isBodyCompletelyEmpty = bodyContentsAreEmpty && !commentPrecedesRightBrace

      if !isBodyCompletelyEmpty {
        after(body.leftBrace, tokens: .close, .close, .break(offset: 2), .open(.consistent, 0))
        before(body.rightBrace, tokens: .break(offset: -2), .close)
      } else {
        // The size-0 break in the empty case allows for a break between the braces in the rare
        // event that the declaration would be exactly the column limit + 1.
        after(body.leftBrace, tokens: .close, .close, .break(size: 0))
      }
    } else {
      // Function-like declarations in protocols won't have bodies, so make sure we close the
      // correct number of groups in that case as well.
      after(node.lastToken, tokens: .close, .close)
    }
    
    after(node.lastToken, tokens: .close)
  }

  // MARK: - Property and subscript accessor block nodes

  override func visit(_ node: AccessorBlockSyntax) {
    if !(node.parent is SubscriptDeclSyntax) {
      // The body may be free of other syntax nodes, but we still need to insert the breaks if it
      // contains a comment (which will be in the leading trivia of the right brace).
      let commentPrecedesRightBrace = node.rightBrace.leadingTrivia.numberOfComments > 0
      let isBodyCompletelyEmpty = isBodyEmpty(node) && !commentPrecedesRightBrace

      if !isBodyCompletelyEmpty {
        after(node.leftBrace, tokens: .break(offset: 2), .open(.consistent, 0))
        before(node.rightBrace, tokens: .break(offset: -2), .close)
      } else {
        // The size-0 break in the empty case allows for a break between the braces in the rare
        // event that the declaration would be exactly the column limit + 1.
        after(node.leftBrace, tokens: .break(size: 0))
      }
    }
    super.visit(node)
  }

  override func visit(_ node: AccessorListSyntax) {
    if node.count > 1 {
      after(node.first?.lastToken, tokens: .break)
    }
    super.visit(node)
  }

  override func visit(_ node: AccessorDeclSyntax) {
    before(node.firstToken, tokens: .space(size: 0), .open(.consistent, 0))

    if let body = node.body {
      before(node.accessorKind, tokens: .open, .open)
      before(body.leftBrace, tokens: .break)

      // The body may be free of other syntax nodes, but we still need to insert the breaks if it
      // contains a comment (which will be in the leading trivia of the right brace).
      let commentPrecedesRightBrace = body.rightBrace.leadingTrivia.numberOfComments > 0
      let isBodyCompletelyEmpty = body.statements.isEmpty && !commentPrecedesRightBrace

      if !isBodyCompletelyEmpty {
        after(body.leftBrace, tokens: .close, .break(offset: 2), .open(.consistent, 0))
        before(body.rightBrace, tokens: .break(offset: -2), .close, .close)
      } else {
        // The size-0 break in the empty case allows for a break between the braces in the rare
        // event that the declaration would be exactly the column limit + 1.
        after(body.leftBrace, tokens: .close, .close, .break(size: 0))
      }
    }

    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: AccessorParameterSyntax) {
    super.visit(node)
  }

  /// Returns a value indicating whether the body of the accessor block (regardless of whether it
  /// contains accessors or statements) is empty.
  private func isBodyEmpty(_ node: AccessorBlockSyntax?) -> Bool {
    guard let node = node else { return true }

    if let accessorList = node.accessorListOrStmtList as? AccessorListSyntax {
      return accessorList.isEmpty
    }
    if let stmtList = node.accessorListOrStmtList as? CodeBlockItemListSyntax {
      return stmtList.isEmpty
    }

    // We shouldn't get here because it should be one of the two above, but to be future-proof,
    // we'll use false if we see something else.
    return false
  }

  // MARK: - Control flow statement nodes

  override func visit(_ node: IfStmtSyntax) {
    after(node.ifKeyword, tokens: .space)

    before(node.conditions.firstToken, tokens: .open(.consistent, 0), .open(.inconsistent, 2))
    after(node.conditions.lastToken, tokens: .close)
    before(node.body.leftBrace, tokens: .break(size: 0), .close, .break)

    arrangeBracesAndContents(of: node.body, contentsKeyPath: \.statements)

    before(node.elseKeyword, tokens: .break(size: maxlinelength))
    after(node.elseKeyword, tokens: .space)

    if let elseBody = node.elseBody as? CodeBlockSyntax {
      arrangeBracesAndContents(of: elseBody, contentsKeyPath: \.statements)
    }

    super.visit(node)
  }

  override func visit(_ node: GuardStmtSyntax) {
    after(node.guardKeyword, tokens: .space)
    after(node.elseKeyword, tokens: .space)

    before(node.conditions.firstToken, tokens: .open(.consistent, 0), .open(.inconsistent, 2))
    after(node.conditions.lastToken, tokens: .close)
    before(node.elseKeyword, tokens: .break(size: 0), .close, .break)

    arrangeBracesAndContents(of: node.body, contentsKeyPath: \.statements)

    super.visit(node)
  }

  override func visit(_ node: ForInStmtSyntax) {
    after(node.labelColon, tokens: .space)
    after(node.forKeyword, tokens: .space)

    before(node.pattern.firstToken, tokens: .open(.consistent, 0), .open(.inconsistent, 0))

    before(node.inKeyword, tokens: .break(offset: 2), .open(.inconsistent, 2))
    after(node.inKeyword, tokens: .space)
    after(node.sequenceExpr.lastToken, tokens: .close)

    before(node.whereClause?.whereKeyword, tokens: .break)
    before(node.body.leftBrace, tokens: .close, .break(size: 0), .close, .break)

    arrangeBracesAndContents(of: node.body, contentsKeyPath: \.statements)

    super.visit(node)
  }

  override func visit(_ node: WhileStmtSyntax) {
    after(node.labelColon, tokens: .space)
    after(node.whileKeyword, tokens: .space)

    before(node.conditions.firstToken, tokens: .open(.consistent, 0), .open(.inconsistent, 2))
    after(node.conditions.lastToken, tokens: .close)
    before(node.body.leftBrace, tokens: .break(size: 0), .close, .break)

    arrangeBracesAndContents(of: node.body, contentsKeyPath: \.statements)

    super.visit(node)
  }

  override func visit(_ node: RepeatWhileStmtSyntax) {
    // The zero-width space prevents the consistent group here from immediately following a break,
    // which would cause all of the breaks immediately inside the group to fire.
    before(
      node.repeatKeyword, tokens: .space(size: 0), .open(.consistent, 0), .open(.inconsistent, 0))
    after(node.repeatKeyword, tokens: .space)

    arrangeBracesAndContents(of: node.body, contentsKeyPath: \.statements)

    before(node.whileKeyword, tokens: .close, .break, .open(.inconsistent, 0))
    after(node.whileKeyword, tokens: .space)

    before(node.condition.firstToken, tokens: .open(.inconsistent, 2))
    after(node.condition.lastToken, tokens: .close, .close, .close)

    super.visit(node)
  }

  override func visit(_ node: DoStmtSyntax) {
    // The zero-width space prevents the consistent group here from immediately following a break,
    // which would cause all of the breaks immediately inside the group to fire.
    before(node.doKeyword, tokens: .space(size: 0), .open(.consistent, 0), .open(.inconsistent, 0))
    after(node.doKeyword, tokens: .space)

    arrangeBracesAndContents(of: node.body, contentsKeyPath: \.statements)

    if let catchClauses = node.catchClauses {
      // If there is only a single `catch` clause, we precede it with a default break so that it
      // only moves to the next line if necessary. If there are multiple `catch` clauses, we use a
      // max-line-length break so that each case is forced onto its own line.
      if catchClauses.count > 1 {
        for catchClause in catchClauses {
          before(catchClause.catchKeyword, tokens: .break(size: maxlinelength))
        }
      } else {
        before(catchClauses[0].catchKeyword, tokens: .close, .break, .open(.inconsistent, 0))
      }
    }

    after(node.lastToken, tokens: .close, .close)

    super.visit(node)
  }

  override func visit(_ node: CatchClauseSyntax) {
    before(node.pattern?.firstToken, tokens: .break)

    if let whereClause = node.whereClause {
      before(whereClause.whereKeyword, tokens: .break, .open(.consistent, 0))
      before(node.body.leftBrace, tokens: .break, .close)
    } else {
      before(node.body.leftBrace, tokens: .break)
    }

    arrangeBracesAndContents(of: node.body, contentsKeyPath: \.statements)

    super.visit(node)
  }

  override func visit(_ node: DeferStmtSyntax) {
    after(node.deferKeyword, tokens: .space)
    arrangeBracesAndContents(of: node.body, contentsKeyPath: \.statements)
    super.visit(node)
  }

  override func visit(_ node: BreakStmtSyntax) {
    before(node.label, tokens: .break(offset: 2))
    super.visit(node)
  }

  override func visit(_ node: ReturnStmtSyntax) {
    before(node.firstToken, tokens: .open)
    before(node.expression?.firstToken, tokens: .break(offset: 2))
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: ThrowStmtSyntax) {
    before(node.expression.firstToken, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: ContinueStmtSyntax) {
    before(node.label, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: SwitchStmtSyntax) {
    before(node.switchKeyword, tokens: .open(.inconsistent, 7))
    after(node.switchKeyword, tokens: .space)
    after(node.expression.lastToken, tokens: .close, .break)

    if !areBracesCompletelyEmpty(node, contentsKeyPath: \.cases) {
      after(node.leftBrace, tokens: .break, .open(.consistent, 0))
      before(node.rightBrace, tokens: .break, .close)
    } else {
      before(node.rightBrace, tokens: .break(size: 0))
    }

    super.visit(node)
  }

  override func visit(_ node: SwitchCaseSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.label.lastToken, tokens: .newline(offset: 2), .open(.consistent, 0))
    insertToken(.newline, betweenChildrenOf: node.statements)
    after(node.lastToken, tokens: .break(offset: -2), .close, .close)
    super.visit(node)
  }

  override func visit(_ node: SwitchCaseLabelSyntax) {
    before(node.caseKeyword, tokens: .open(.inconsistent, 5))
    after(node.caseKeyword, tokens: .space)
    after(node.colon, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: CaseItemSyntax) {
    before(node.firstToken, tokens: .open)
    before(node.whereClause?.firstToken, tokens: .break)
    if let trailingComma = node.trailingComma {
      after(trailingComma, tokens: .close, .break)
    } else {
      after(node.lastToken, tokens: .close)
    }
    super.visit(node)
  }

  override func visit(_ node: SwitchDefaultLabelSyntax) {
    // Implementation not needed.
    super.visit(node)
  }

  // TODO: - Other nodes (yet to be organized)

  override func visit(_ node: DeclNameArgumentsSyntax) {
    super.visit(node)
  }

  override func visit(_ node: BinaryOperatorExprSyntax) {
    switch node.operatorToken.tokenKind {
    case .unspacedBinaryOperator:
      break
    default:
      before(node.operatorToken, tokens: .break)
      after(node.operatorToken, tokens: .break)
    }
    super.visit(node)
  }

  override func visit(_ node: TupleExprSyntax) {
    after(
      node.leftParen,
      tokens: .break(size: 0, offset: 2), .open(.consistent, 0), .break(size: 0),
        .open(.inconsistent, 0)
    )
    before(node.rightParen, tokens: .close, .break(size: 0, offset: -2), .close)
    super.visit(node)
  }

  override func visit(_ node: TupleElementListSyntax) {
    insertToken(.break, betweenChildrenOf: node)
    super.visit(node)
  }

  override func visit(_ node: TupleElementSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.colon, tokens: .break)
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: ArrayExprSyntax) {
    after(
      node.leftSquare,
      tokens: .break(size: 0, offset: 2), .open(.consistent, 0), .break(size: 0),
        .open(.consistent, 0)
    )
    before(node.rightSquare, tokens: .close, .break(size: 0, offset: -2), .close)
    super.visit(node)
  }

  override func visit(_ node: ArrayElementListSyntax) {
    insertToken(.break, betweenChildrenOf: node)
    super.visit(node)
  }

  override func visit(_ node: ArrayElementSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: DictionaryExprSyntax) {
    after(
      node.leftSquare,
      tokens: .break(size: 0, offset: 2), .open(.consistent, 0), .break(size: 0),
      .open(.consistent, 0)
    )
    before(node.rightSquare, tokens: .close, .break(size: 0, offset: -2), .close)
    super.visit(node)
  }

  override func visit(_ node: DictionaryElementListSyntax) {
    insertToken(.break, betweenChildrenOf: node)
    super.visit(node)
  }

  override func visit(_ node: DictionaryTypeSyntax) {
    after(node.colon, tokens: .space)
    super.visit(node)
  }

  override func visit(_ node: DictionaryElementSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.colon, tokens: .break(offset: 2))
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: ImplicitMemberExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: FunctionParameterSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.colon, tokens: .break)
    before(node.secondName, tokens: .break)

    if let trailingComma = node.trailingCommaWorkaround {
      after(trailingComma, tokens: .close, .break)
    } else {
      after(node.lastToken, tokens: .close)
    }
    super.visit(node)
  }

  override func visit(_ node: MemberAccessExprSyntax) {
    before(node.firstToken, tokens: .open(.inconsistent, 0))
    before(node.dot, tokens: .break(size: 0, offset: 2))
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: FunctionCallExprSyntax) {
    if node.argumentList.count == 1, node.argumentList[0].expression is ClosureExprSyntax {
      super.visit(node)
      return
    }
    if node.argumentList.count > 0 {
      after(node.leftParen, tokens: .break(size: 0, offset: 2), .open(.consistent, 0))
      before(node.rightParen, tokens: .close)
    }
    before(node.trailingClosure?.leftBrace, tokens: .space, .reset)
    super.visit(node)
  }

  override func visit(_ node: FunctionCallArgumentSyntax) {
    after(node.colon, tokens: .break)
    before(node.firstToken, tokens: .open)
    if let trailingComma = node.trailingComma {
      after(trailingComma, tokens: .close, .break)
    } else {
      after(node.lastToken, tokens: .close)
    }
    super.visit(node)
  }

  override func visit(_ node: ClosureExprSyntax) {
    if let signature = node.signature {
      before(signature.firstToken, tokens: .break(offset: 2))
      if node.statements.count > 0 {
        after(signature.inTok, tokens: .newline(offset: 2), .open(.consistent, 0))
      } else {
        after(signature.inTok, tokens: .break(size: 0, offset: 2), .open(.consistent, 0))
      }
      before(node.rightBrace, tokens: .break(offset: -2), .close)
    } else if node.statements.count > 0 {
      after(node.leftBrace, tokens: .break(offset: 2), .open(.consistent, 0))
      before(node.rightBrace, tokens: .break(offset: -2), .close)
    }
    super.visit(node)
  }

  override func visit(_ node: ClosureParamSyntax) {
    after(node.trailingComma, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: ClosureSignatureSyntax) {
    before(node.firstToken, tokens: .open(.inconsistent, 0))
    after(node.capture?.lastToken, tokens: .break)
    before(node.input?.firstToken, tokens: .open)
    after(node.input?.lastToken, tokens: .close, .break)
    after(node.output?.lastToken, tokens: .break)
    after(node.throwsTok, tokens: .break)
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: ClosureCaptureSignatureSyntax) {
    after(node.leftSquare, tokens: .break(size: 0, offset: 2), .open(.consistent, 0))
    before(node.rightSquare, tokens: .break(size: 0, offset: -2), .close)
    super.visit(node)
  }

  override func visit(_ node: ClosureCaptureItemSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.specifier?.lastToken, tokens: .break)
    before(node.assignToken, tokens: .break)
    after(node.assignToken, tokens: .break)
    if let trailingComma = node.trailingComma {
      before(trailingComma, tokens: .close)
      after(trailingComma, tokens: .break)
    } else {
      after(node.lastToken, tokens: .close)
    }
    super.visit(node)
  }

  override func visit(_ node: SubscriptExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: ExpressionSegmentSyntax) {
    verbatimToken(node)
    // Call to super.visit is not needed here.
  }

  override func visit(_ node: ObjcKeyPathExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: AssignmentExprSyntax) {
    before(node.assignToken, tokens: .break)
    after(node.assignToken, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: ObjectLiteralExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: ParameterClauseSyntax) {
    after(node.leftParen, tokens: .break(size: 0, offset: 2), .open(.consistent, 0))
    before(node.rightParen, tokens: .break(size: 0, offset: -2), .close)
    super.visit(node)
  }

  override func visit(_ node: ReturnClauseSyntax) {
    before(node.firstToken, tokens: .open)
    before(node.returnType.firstToken, tokens: .break)
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: IfConfigDeclSyntax) {
    super.visit(node)
  }

  override func visit(_ node: IfConfigClauseSyntax) {
    switch node.poundKeyword.tokenKind {
    case .poundIfKeyword, .poundElseifKeyword:
      after(node.poundKeyword, tokens: .break)
    case .poundElseKeyword:
      break
    default:
      preconditionFailure()
    }
    before(node.elements.firstToken, tokens: .newline(offset: 2), .open(.consistent, 0))
    after(node.elements.lastToken, tokens: .newline(offset: -2), .close)
    super.visit(node)
  }

  override func visit(_ node: MemberDeclBlockSyntax) {
    // Ordinarily, we would use `insertToken` here, but it causes a build error for an unknown
    // reason.
    if node.members.count > 1 {
      for i in 0..<(node.members.count - 1) {
        after(node.members[i].lastToken, tokens: .break(size: maxlinelength))
      }
    }
    super.visit(node)
  }

  override func visit(_ node: SourceFileSyntax) {
    super.visit(node)
  }

  override func visit(_ node: EnumCaseDeclSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.caseKeyword, tokens: .break)
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: OperatorDeclSyntax) {
    super.visit(node)
  }

  override func visit(_ node: EnumCaseElementSyntax) {
    after(node.trailingComma, tokens: .break(offset: 2))
    super.visit(node)
  }

  override func visit(_ node: ObjcSelectorExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: InfixOperatorGroupSyntax) {
    super.visit(node)
  }

  override func visit(_ node: PrecedenceGroupDeclSyntax) {
    super.visit(node)
  }

  override func visit(_ node: PrecedenceGroupRelationSyntax) {
    super.visit(node)
  }

  override func visit(_ node: PrecedenceGroupAssignmentSyntax) {
    super.visit(node)
  }

  override func visit(_ node: PrecedenceGroupNameElementSyntax) {
    super.visit(node)
  }

  override func visit(_ node: PrecedenceGroupAssociativitySyntax) {
    super.visit(node)
  }

  override func visit(_ node: AccessLevelModifierSyntax) {
    super.visit(node)
  }

  override func visit(_ node: CodeBlockSyntax) {
    insertToken(.break(size: maxlinelength), betweenChildrenOf: node.statements)
    super.visit(node)
  }

  override func visit(_ node: CodeBlockItemListSyntax) {
    if node.parent is AccessorBlockSyntax || node.parent is ClosureExprSyntax ||
       node.parent is IfConfigClauseSyntax, node.count > 0 {
      insertToken(.break(size: maxlinelength), betweenChildrenOf: node)
    }
    super.visit(node)
  }

  override func visit(_ node: CodeBlockItemSyntax) {
    before(node.firstToken, tokens: .open)
    if !(node.parent?.parent is CodeBlockSyntax ||
           node.parent?.parent is SwitchCaseSyntax ||
           node.parent?.parent is ClosureExprSyntax ||
           node.parent?.parent is AccessorBlockSyntax ||
           node.parent?.parent is IfConfigClauseSyntax
         ) {
      after(node.lastToken, tokens: .close, .break(size: maxlinelength))
    } else {
      after(node.lastToken, tokens: .close)
    }
    super.visit(node)
  }

  override func visit(_ node: GenericParameterClauseSyntax) {
    after(node.leftAngleBracket, tokens: .break(size: 0, offset: 2), .open(.consistent, 0))
    before(node.rightAngleBracket, tokens: .break(size: 0, offset: -2), .close)
    super.visit(node)
  }

  override func visit(_ node: ArrayTypeSyntax) {
    super.visit(node)
  }

  override func visit(_ node: TupleTypeSyntax) {
    after(node.leftParen, tokens: .open(.consistent, 2), .break(size: 0))
    before(node.rightParen, tokens: .break(size: 0), .close)
    super.visit(node)
  }

  override func visit(_ node: FunctionTypeSyntax) {
    after(node.leftParen, tokens: .break(size: 0, offset: 2), .open(.consistent, 0))
    before(node.rightParen, tokens: .break(size: 0, offset: -2), .close)
    before(node.throwsOrRethrowsKeyword, tokens: .break)
    before(node.arrow, tokens: .break)
    before(node.returnType.firstToken, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: GenericArgumentClauseSyntax) {
    after(node.leftAngleBracket, tokens: .break(size: 0, offset: 2), .open(.consistent, 0))
    before(node.rightAngleBracket, tokens: .break(size: 0, offset: -2), .close)
    super.visit(node)
  }

  override func visit(_ node: TuplePatternSyntax) {
    after(node.leftParen, tokens: .open(.consistent, 2), .break(size: 0))
    before(node.rightParen, tokens: .break(size: 0), .close)
    super.visit(node)
  }

  override func visit(_ node: AsExprSyntax) {
    before(node.asTok, tokens: .break)
    before(node.typeName.firstToken, tokens: .space)
    super.visit(node)
  }

  override func visit(_ node: IsExprSyntax) {
    before(node.isTok, tokens: .space)
    after(node.isTok, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: TryExprSyntax) {
    before(node.expression.firstToken, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: TypeExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: ArrowExprSyntax) {
    before(node.throwsToken, tokens: .break)
    before(node.arrowToken, tokens: .break)
    after(node.arrowToken, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: AttributeSyntax) {
    if node.balancedTokens.count > 0 {
      for i in 0..<(node.balancedTokens.count - 1) {
        let tokens = node.balancedTokens
        switch (tokens[i].tokenKind, tokens[i+1].tokenKind) {
        case (.leftParen, _): ()
        case (_, .rightParen): ()
        case (_, .comma): ()
        case (_, .colon): ()
        default:
          after(tokens[i], tokens: .space)
        }
      }
      after(node.balancedTokens.lastToken, tokens: .newline)
    } else {
      if node.parent?.parent is ImportDeclSyntax {
        after(node.lastToken, tokens: .space)
      } else {
        after(node.lastToken, tokens: .break)
      }
    }
    super.visit(node)
  }

  override func visit(_ node: ElseBlockSyntax) {
    super.visit(node)
  }

  override func visit(_ node: ConditionElementSyntax) {
    after(node.trailingComma, tokens:. break)
    super.visit(node)
  }

  override func visit(_ node: InOutExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: ImportDeclSyntax) {
    after(node.importTok, tokens: .space)
    after(node.importKind, tokens: .space)
    super.visit(node)
  }

  override func visit(_ node: DotSelfExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: KeyPathExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: TernaryExprSyntax) {
    before(node.conditionExpression.firstToken, tokens: .open(.inconsistent, 2))
    before(node.questionMark, tokens: .break)
    after(node.questionMark, tokens: .space)
    before(node.colonMark, tokens: .break)
    after(node.colonMark, tokens: .space)
    after(node.secondChoice.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: WhereClauseSyntax) {
    before(node.whereKeyword, tokens: .open(.inconsistent, 2))
    after(node.whereKeyword, tokens: .space)
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: DeclModifierSyntax) {
    after(node.lastToken, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: FunctionSignatureSyntax) {
    before(node.throwsOrRethrowsKeyword, tokens: .break)
    before(node.output?.firstToken, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: MetatypeTypeSyntax) {
    super.visit(node)
  }

  override func visit(_ node: OptionalTypeSyntax) {
    super.visit(node)
  }

  override func visit(_ node: SequenceExprSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: SuperRefExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: VariableDeclSyntax) {
    if let attributes = node.attributes {
      before(node.firstToken, tokens: .space(size: 0), .open(.consistent, 0))
      after(attributes.lastToken, tokens: .open)
    } else {
      before(node.firstToken, tokens: .space(size: 0), .open(.consistent, 0), .open)
    }
    after(node.lastToken, tokens: .close, .close)
    after(node.letOrVarKeyword, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: AsTypePatternSyntax) {
    super.visit(node)
  }

  override func visit(_ node: InheritedTypeSyntax) {
    before(node.firstToken, tokens: .open(.inconsistent, 0))
    if let trailingComma = node.trailingComma {
      after(trailingComma, tokens: .close, .break)
    } else {
      after(node.lastToken, tokens: .close)
    }
    super.visit(node)
  }

  override func visit(_ node: IsTypePatternSyntax) {
    after(node.isKeyword, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: ObjcNamePieceSyntax) {
    super.visit(node)
  }

  override func visit(_ node: PoundFileExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: PoundLineExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: StringSegmentSyntax) {
    super.visit(node)
  }

  override func visit(_ node: TypealiasDeclSyntax) {
    if let attributes = node.attributes {
      before(node.firstToken, tokens: .space(size: 0), .open(.consistent, 0))
      after(attributes.lastToken, tokens: .open)
    } else {
      before(node.firstToken, tokens: .space(size: 0), .open(.consistent, 0), .open)
    }
    after(node.lastToken, tokens: .close, .close)
    after(node.typealiasKeyword, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: TypeInitializerClauseSyntax) {
    before(node.equal, tokens: .break)
    after(node.equal, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: AttributedTypeSyntax) {
    after(node.specifier, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: ExpressionStmtSyntax) {
    super.visit(node)
  }

  override func visit(_ node: IdentifierExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: NilLiteralExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: PatternBindingSyntax) {
    before(node.accessor?.firstToken, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: PoundErrorDeclSyntax) {
    super.visit(node)
  }

  override func visit(_ node: SpecializeExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: TypeAnnotationSyntax) {
    after(node.colon, tokens: .break(offset: 2))
    super.visit(node)
  }

  override func visit(_ node: UnknownPatternSyntax) {
    super.visit(node)
  }

  override func visit(_ node: CompositionTypeSyntax) {
    super.visit(node)
  }

  override func visit(_ node: CompositionTypeElementSyntax) {
    if let ampersand = node.ampersand {
      before(ampersand, tokens: .break)
      after(ampersand, tokens: .space)
    }
    super.visit(node)
  }

  override func visit(_ node: DeclarationStmtSyntax) {
    super.visit(node)
  }

  override func visit(_ node: EnumCasePatternSyntax) {
    super.visit(node)
  }

  override func visit(_ node: FallthroughStmtSyntax) {
    super.visit(node)
  }

  override func visit(_ node: ForcedValueExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: GenericArgumentSyntax) {
    before(node.firstToken, tokens: .open)
    if let trailingComma = node.trailingComma {
      after(trailingComma, tokens: .close, .break)
    } else {
      after(node.lastToken, tokens: .close)
    }
    super.visit(node)
  }

  override func visit(_ node: OptionalPatternSyntax) {
    super.visit(node)
  }

  override func visit(_ node: PoundColumnExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: WildcardPatternSyntax) {
    super.visit(node)
  }

  override func visit(_ node: DeclNameArgumentSyntax) {
    super.visit(node)
  }

  override func visit(_ node: FloatLiteralExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: GenericParameterSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.colon, tokens: .break)
    if let trailingComma = node.trailingComma {
      after(trailingComma, tokens: .close, .break)
    } else {
      after(node.lastToken, tokens: .close)
    }
    super.visit(node)
  }

  override func visit(_ node: PostfixUnaryExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: PoundWarningDeclSyntax) {
    super.visit(node)
  }

  override func visit(_ node: TupleTypeElementSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.colon, tokens: .break)
    before(node.secondNameWorkaround, tokens: .break)

    if let trailingComma = node.trailingCommaWorkaround {
      after(trailingComma, tokens: .close, .break)
    } else {
      after(node.lastToken, tokens: .close)
    }
    super.visit(node)
  }

  override func visit(_ node: ExpressionPatternSyntax) {
    super.visit(node)
  }

  override func visit(_ node: ValueBindingPatternSyntax) {
    after(node.letOrVarKeyword, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: IdentifierPatternSyntax) {
    super.visit(node)
  }

  override func visit(_ node: InitializerClauseSyntax) {
    before(node.equal, tokens: .break)
    after(node.equal, tokens: .break(offset: 2))

    super.visit(node)
  }

  override func visit(_ node: PoundFunctionExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: StringLiteralExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: AssociatedtypeDeclSyntax) {
    if let attributes = node.attributes {
      before(node.firstToken, tokens: .space(size: 0), .open(.consistent, 0))
      after(attributes.lastToken, tokens: .open)
    } else {
      before(node.firstToken, tokens: .space(size: 0), .open(.consistent, 0), .open)
    }
    after(node.lastToken, tokens: .close, .close)
    after(node.associatedtypeKeyword, tokens: .break)
    before(node.genericWhereClause?.firstToken, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: BooleanLiteralExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: ElseIfContinuationSyntax) {
    super.visit(node)
  }

  override func visit(_ node: GenericWhereClauseSyntax) {
    before(node.whereKeyword, tokens: .open(.consistent, 2))
    after(node.whereKeyword, tokens: .break)
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: IntegerLiteralExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: PoundDsohandleExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: PrefixOperatorExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: AccessPathComponentSyntax) {
    super.visit(node)
  }

  override func visit(_ node: SameTypeRequirementSyntax) {
    before(node.firstToken, tokens: .open)
    before(node.equalityToken, tokens: .break)
    after(node.equalityToken, tokens: .break)
    if let trailingComma = node.trailingComma {
      after(trailingComma, tokens: .close, .break)
    } else {
      after(node.lastToken, tokens: .close)
    }
    super.visit(node)
  }

  override func visit(_ node: TuplePatternElementSyntax) {
    after(node.trailingComma, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: MemberTypeIdentifierSyntax) {
    super.visit(node)
  }

  override func visit(_ node: OptionalChainingExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: SimpleTypeIdentifierSyntax) {
    super.visit(node)
  }

  override func visit(_ node: AvailabilityConditionSyntax) {
    super.visit(node)
  }

  override func visit(_ node: DiscardAssignmentExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: EditorPlaceholderExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: SymbolicReferenceExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: TypeInheritanceClauseSyntax) {
    after(node.colon, tokens: .break(offset: 2))
    before(node.inheritedTypeCollection.firstToken, tokens: .open(.consistent, 0))
    after(node.inheritedTypeCollection.lastToken, tokens: .break(size: 0, offset: -2), .close)
    super.visit(node)
  }

  override func visit(_ node: UnresolvedPatternExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: ConformanceRequirementSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.colon, tokens: .break)
    if let trailingComma = node.trailingComma {
      after(trailingComma, tokens: .close, .break)
    } else {
      after(node.lastToken, tokens: .close)
    }
    super.visit(node)
  }

  override func visit(_ node: StringInterpolationExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: MatchingPatternConditionSyntax) {
    before(node.firstToken, tokens: .open(.inconsistent, 2))
    after(node.caseKeyword, tokens: .break)
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: OptionalBindingConditionSyntax) {
    before(node.firstToken, tokens: .open(.inconsistent, 2))
    after(node.letOrVarKeyword, tokens: .break)
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: ImplicitlyUnwrappedOptionalTypeSyntax) {
    super.visit(node)
  }

  override func visit(_ node: UnknownDeclSyntax) {
    verbatimToken(node)
    // Call to super.visit is not needed here.
  }

  override func visit(_ node: UnknownStmtSyntax) {
    verbatimToken(node)
    // Call to super.visit is not needed here.
  }

  override func visit(_ token: TokenSyntax) {
    extractLeadingTrivia(token)
    let keepExistingNewline = config.respectsExistingLineBreaks && newlinePrecedes(token)
    if let before = beforeMap[token] {
      appendTokens(before, keepExistingNewline: keepExistingNewline, originatingFrom: token)
    }

    appendToken(.syntax(token))

    extractTrailingComment(token)
    if let afterGroups = afterMap[token] {
      for after in afterGroups.reversed() {
        tokens += after
      }
    }
  }

  // MARK: - Various other helper methods

  /// Returns a value indicating whether or not the given braced syntax node is completely empty;
  /// that is, it contains neither child syntax nodes (aside from the braces) *nor* any comments.
  ///
  /// Checking for comments separately is vitally important, because a code block that appears to be
  /// "empty" because it doesn't contain any statements might still contain comments, and if those
  /// are line comments, we need to make sure to insert the same breaks that we would if there were
  /// other statements there to get the same layout.
  ///
  /// - Parameters:
  ///   - node: A node that conforms to `BracedSyntax`.
  ///   - contentsKeyPath: A keypath describing how to get from `node` to the contents of the node
  ///     (a `Collection` whose elements conform to `Syntax`; this will most likely be an instance
  ///     of one of the `*ListSyntax` types).
  /// - Returns: True if the collection at the node's keypath is empty and there are no comments
  private func areBracesCompletelyEmpty<Node: BracedSyntax, BodyContents: Collection>(
    _ node: Node,
    contentsKeyPath: KeyPath<Node, BodyContents>
  ) -> Bool where BodyContents.Element: Syntax {
    // If the collection is empty, then any comments that might be present in the block must be
    // leading trivia of the right brace.
    let commentPrecedesRightBrace = node.rightBrace.leadingTrivia.numberOfComments > 0
    return node[keyPath: contentsKeyPath].isEmpty && !commentPrecedesRightBrace
  }

  /// Returns a value indicating whether or not the given braced syntax node is completely empty;
  /// that is, it contains neither child syntax nodes (aside from the braces) *nor* any comments.
  ///
  /// Checking for comments separately is vitally important, because a code block that appears to be
  /// "empty" because it doesn't contain any statements might still contain comments, and if those
  /// are line comments, we need to make sure to insert the same breaks that we would if there were
  /// other statements there to get the same layout.
  ///
  /// Note the slightly different generic constraint on this overload. Both are required because
  /// protocols in Swift do not conform to themselves, so if the element type of the collection is
  /// *precisely* `Syntax`, the constraint `BodyContents.Element: Syntax` is not satisfied.
  ///
  /// - Parameters:
  ///   - node: A node that conforms to `BracedSyntax`.
  ///   - contentsKeyPath: A keypath describing how to get from `node` to the contents of the node
  ///     (a `Collection` whose elements are exactly of type `Syntax`; this will most likely be an
  ///     instance of one of the `*ListSyntax` types).
  /// - Returns: True if the collection at the node's keypath is empty and there are no comments
  private func areBracesCompletelyEmpty<Node: BracedSyntax, BodyContents: Collection>(
    _ node: Node,
    contentsKeyPath: KeyPath<Node, BodyContents>
  ) -> Bool where BodyContents.Element == Syntax {
    // If the collection is empty, then any comments that might be present in the block must be
    // leading trivia of the right brace.
    let commentPrecedesRightBrace = node.rightBrace.leadingTrivia.numberOfComments > 0
    return node[keyPath: contentsKeyPath].isEmpty && !commentPrecedesRightBrace
  }

  /// Applies consistent formatting to the braces and contents of the given node.
  ///
  /// - Parameters:
  ///   - node: A node that conforms to `BracedSyntax`.
  ///   - contentsKeyPath: A keypath describing how to get from `node` to the contents of the node
  ///     (a `Collection` whose elements conform to `Syntax`; this will most likely be an instance
  ///     of one of the `*ListSyntax` types).
  private func arrangeBracesAndContents<Node: BracedSyntax, BodyContents: Collection>(
    of node: Node,
    contentsKeyPath: KeyPath<Node, BodyContents>
  ) where BodyContents.Element: Syntax {
    if !areBracesCompletelyEmpty(node, contentsKeyPath: contentsKeyPath) {
      after(node.leftBrace, tokens: .break(offset: 2), .open(.consistent, 0))
      before(node.rightBrace, tokens: .break(offset: -2), .close)
    } else {
      before(node.rightBrace, tokens: .break(size: 0))
    }
  }

  /// Returns `true` iff the content of the given token is immediately preceded by a newline
  /// (ignoring whitespace and backticks).
  private func newlinePrecedes(_ token: TokenSyntax?) -> Bool {
    guard let token = token else { return false }

    for piece in token.leadingTrivia.reversed() {
      switch piece {
      case .carriageReturns, .carriageReturnLineFeeds, .newlines:
        return true
      case .spaces, .tabs, .backticks:
        continue
      default:
        return false
      }
    }
    return false
  }

  /// Appends the given tokens to the stream, optionally keeping an existing newline that may be
  /// present at the first break.
  private func appendTokens(
    _ newTokens: [Token],
    keepExistingNewline: Bool,
    originatingFrom syntaxToken: TokenSyntax
  ) {
    var convertBreakToNewline = keepExistingNewline
    for token in newTokens {
      if convertBreakToNewline, case .break(_, let offset) = token {
        // To keep the existing newline, we need to change the `break` token's length to be the
        // maximum length of the line, to force it to wrap when laid out.
        tokens.append(.break(size: maxlinelength, offset: offset))
        convertBreakToNewline = false
      } else if case .close = token {
        if keepExistingNewline && convertBreakToNewline && syntaxToken.text == ")" {
          // If we haven't seen a break yet and we're about to close a parenthesis-delimited group,
          // we need to insert our own break with a -2 offset to generate the newline and put the
          // parenthesis in the correct place.
          tokens.append(.break(size: maxlinelength, offset: -2))
        }
        tokens.append(token)
      } else {
        tokens.append(token)
      }
    }
  }

  private func extractTrailingComment(_ token: TokenSyntax) {
    let nextToken = token.nextToken
    guard let trivia = nextToken?.leadingTrivia,
          let firstPiece = trivia[safe: 0] else {
      return
    }

    let commentToken: Comment
    let position = token.endPositionAfterTrailingTrivia
    switch firstPiece {
    case .lineComment(let text):
      commentToken = Comment(kind: .line, text: text, position: position)
    case .blockComment(let text):
      commentToken = Comment(kind: .block, text: text, position: position)
    default:
      return
    }

    appendToken(.break(size: 2, offset: 0))
    appendToken(.comment(commentToken, wasEndOfLine: true))

    if nextToken != nil, ["}", ")", "]"].contains(nextToken?.withoutTrivia().text), trivia.numberOfComments == 1 {
      appendToken(.break(size: maxlinelength, offset: -2))
    } else {
      appendToken(.break(size: maxlinelength))
    }
  }

  /// Returns the offset of the first break that was registered for the given syntax token, or zero
  /// if no break was found.
  private func breakOffsetBefore(token: TokenSyntax) -> Int {
    if let befores = beforeMap[token] {
      for before in befores.reversed() {
        if case .break(_, let offset) = before {
          return offset
        }
      }
    }
    return 0
  }

  private func extractLeadingTrivia(_ token: TokenSyntax) {
    let isStartOfFile = token.previousToken == nil
    let trivia = token.leadingTrivia

    for (index, piece) in trivia.enumerated() {
      switch piece {
      case .lineComment(let text):
        if index > 0 || isStartOfFile {
          if token.withoutTrivia().text == "}" {
            if let previousToken = token.previousToken,
              (["{", "in"].contains { $0 == previousToken.withoutTrivia().text }) {
              // do nothing
            } else {
              appendToken(.break(size: maxlinelength))
            }
          }

          let commentOffset = breakOffsetBefore(token: token)
          if !isStartOfFile {
            appendToken(.break(size: maxlinelength, offset: commentOffset))
          }
          appendToken(.comment(Comment(kind: .line, text: text), wasEndOfLine: false))
          appendToken(.break(size: maxlinelength, offset: commentOffset))
        }

      case .blockComment(let text):
        if index > 0 || isStartOfFile {
          if token.withoutTrivia().text == "}" {
            if let previousToken = token.previousToken,
              previousToken.withoutTrivia().text == "{" {
              // do nothing
            } else {
              appendToken(.break(size: maxlinelength))
            }
          }

          let commentOffset = breakOffsetBefore(token: token)
          if !isStartOfFile {
            appendToken(.break(size: maxlinelength, offset: commentOffset))
          }
          appendToken(.comment(Comment(kind: .block, text: text), wasEndOfLine: false))
          appendToken(.break(size: maxlinelength, offset: commentOffset))
        }

      case .docLineComment(let text):
        appendToken(.comment(Comment(kind: .docLine, text: text), wasEndOfLine: false))
        if case .newlines? = trivia[safe: index + 1],
           case .docLineComment? = trivia[safe: index + 2] {
          // do nothing
        } else {
          appendToken(.newline)
        }

      case .docBlockComment(let text):
        appendToken(.comment(Comment(kind: .docBlock, text: text), wasEndOfLine: false))
        appendToken(.newline)

      case .newlines(let n), .carriageReturns(let n), .carriageReturnLineFeeds(let n):
        if n > 1 {
          appendToken(.newlines(min(n - 1, config.maximumBlankLines), offset: 0))
        }

      default:
        break
      }
    }
  }

  func appendToken(_ token: Token) {
    if let last = tokens.last {
      switch (last, token) {
      case (.comment(let c1, _), .comment(let c2, _))
      where c1.kind == .docLine && c2.kind == .docLine:
        var newComment = c1
        newComment.addText(c2.text)
        tokens[tokens.count - 1] = .comment(newComment, wasEndOfLine: false)
        return

      case (.newlines(let N1, let offset1), .newlines(let N2, let offset2)):
        tokens[tokens.count - 1] = .newlines(N1 + N2, offset: offset1 + offset2)
        return

      default:
        break
      }
    }
    tokens.append(token)
  }
}

extension Syntax {
  /// Creates a pretty-printable token stream for the provided Syntax node.
  func makeTokenStream(configuration: Configuration) -> [Token] {
    return TokenStreamCreator(configuration: configuration).makeStream(from: self)
  }
}

extension Collection {
  subscript(safe index: Index) -> Element? {
    return index < endIndex ? self[index] : nil
  }
}
