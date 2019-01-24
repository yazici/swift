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
    before(token, tokens: tokens)
  }

  func before(_ token: TokenSyntax?, tokens: [Token]) {
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
    after(token, tokens: tokens)
  }

  func after(_ token: TokenSyntax?, tokens: [Token]) {
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

  private func insertTokens<Node: Collection>(
    _ tokens: Token...,
    betweenElementsOf collectionNode: Node
  ) where Node.Element: Syntax {
    for element in collectionNode.dropLast() {
      after(element.lastToken, tokens: tokens)
    }
  }

  private func insertTokens<Node: Collection>(
    _ tokens: Token...,
    betweenElementsOf collectionNode: Node
  ) where Node.Element == DeclSyntax {
    for element in collectionNode.dropLast() {
      after(element.lastToken, tokens: tokens)
    }
  }

  private func verbatimToken(_ node: Syntax) {
    if let firstToken = node.firstToken, let before = beforeMap[firstToken] {
      tokens += before
    }
    appendToken(.verbatim(Verbatim(text: node.description)))
    if let lastToken = node.lastToken {
      // Extract any comments that trail the verbatim block since they belong to the next syntax
      // token. Leading comments don't need special handling since they belong to the current node,
      // and will get printed.
      extractTrailingComment(lastToken)
      if let afterGroups = afterMap[lastToken] {
        for after in afterGroups.reversed() {
          tokens += after
        }
      }
    }
  }

  override func visitPre(_ node: Syntax) {}

  // MARK: - Type declaration nodes

  override func visit(_ node: ClassDeclSyntax) {
    arrangeTypeDeclBlock(
      node,
      attributes: node.attributes,
      modifiers: node.modifiers,
      typeKeyword: node.classKeyword,
      identifier: node.identifier,
      genericParameterClause: node.genericParameterClause,
      inheritanceClause: node.inheritanceClause,
      genericWhereClause: node.genericWhereClause,
      members: node.members)
    super.visit(node)
  }

  override func visit(_ node: StructDeclSyntax) {
    arrangeTypeDeclBlock(
      node,
      attributes: node.attributes,
      modifiers: node.modifiers,
      typeKeyword: node.structKeyword,
      identifier: node.identifier,
      genericParameterClause: node.genericParameterClause,
      inheritanceClause: node.inheritanceClause,
      genericWhereClause: node.genericWhereClause,
      members: node.members)
    super.visit(node)
  }

  override func visit(_ node: EnumDeclSyntax) {
    arrangeTypeDeclBlock(
      node,
      attributes: node.attributes,
      modifiers: node.modifiers,
      typeKeyword: node.enumKeyword,
      identifier: node.identifier,
      genericParameterClause: node.genericParameters,
      inheritanceClause: node.inheritanceClause,
      genericWhereClause: node.genericWhereClause,
      members: node.members)
    super.visit(node)
  }

  override func visit(_ node: ProtocolDeclSyntax) {
    arrangeTypeDeclBlock(
      node,
      attributes: node.attributes,
      modifiers: node.modifiers,
      typeKeyword: node.protocolKeyword,
      identifier: node.identifier,
      genericParameterClause: nil,
      inheritanceClause: node.inheritanceClause,
      genericWhereClause: node.genericWhereClause,
      members: node.members)
    super.visit(node)
  }

  override func visit(_ node: ExtensionDeclSyntax) {
    guard let lastTokenOfExtendedType = node.extendedType.lastToken else {
      fatalError("ExtensionDeclSyntax.extendedType must have at least one token")
    }
    arrangeTypeDeclBlock(
      node,
      attributes: node.attributes,
      modifiers: node.modifiers,
      typeKeyword: node.extensionKeyword,
      identifier: lastTokenOfExtendedType,
      genericParameterClause: nil,
      inheritanceClause: node.inheritanceClause,
      genericWhereClause: node.genericWhereClause,
      members: node.members)
    super.visit(node)
  }

  /// Applies formatting tokens to the tokens in the given type declaration node (i.e., a class,
  /// struct, enum, protocol, or extension).
  private func arrangeTypeDeclBlock(
    _ node: Syntax,
    attributes: AttributeListSyntax?,
    modifiers: ModifierListSyntax?,
    typeKeyword: TokenSyntax,
    identifier: TokenSyntax,
    genericParameterClause: GenericParameterClauseSyntax?,
    inheritanceClause: TypeInheritanceClauseSyntax?,
    genericWhereClause: GenericWhereClauseSyntax?,
    members: MemberDeclBlockSyntax
  ) {
    before(node.firstToken, tokens: .open)

    arrangeAttributeList(attributes)

    // Prioritize keeping "<modifiers> <keyword> <name>:" together (corresponding group close is
    // below at `lastTokenBeforeBrace`).
    let firstTokenAfterAttributes = modifiers?.firstToken ?? typeKeyword
    before(firstTokenAfterAttributes, tokens: .open)
    after(typeKeyword, tokens: .break)

    arrangeBracesAndContents(of: members, contentsKeyPath: \.members)

    if let genericWhereClause = genericWhereClause {
      before(genericWhereClause.firstToken, tokens: .break(.same), .open)
      after(members.leftBrace, tokens: .close)
    }

    let lastTokenBeforeBrace =
      inheritanceClause?.colon ?? genericParameterClause?.rightAngleBracket ?? identifier
    after(lastTokenBeforeBrace, tokens: .close)

    after(node.lastToken, tokens: .close)
  }

  // MARK: - Function and function-like declaration nodes (initializers, deinitializers, subscripts)

  override func visit(_ node: FunctionDeclSyntax) {
    // Prioritize keeping "<modifiers> func <name>" together.
    let firstTokenAfterAttributes = node.modifiers?.firstToken ?? node.funcKeyword
    before(firstTokenAfterAttributes, tokens: .open)
    after(node.funcKeyword, tokens: .break)
    after(node.identifier, tokens: .close)

    if case .spacedBinaryOperator = node.identifier.tokenKind {
      after(node.identifier.lastToken, tokens: .space)
    }

    arrangeFunctionLikeDecl(
      node,
      attributes: node.attributes,
      genericWhereClause: node.genericWhereClause,
      body: node.body,
      bodyContentsKeyPath: \.statements)

    super.visit(node)
  }

  override func visit(_ node: InitializerDeclSyntax) {
    // Prioritize keeping "<modifiers> init<punctuation>" together.
    let firstTokenAfterAttributes = node.modifiers?.firstToken ?? node.initKeyword
    let lastTokenOfName = node.optionalMark ?? node.initKeyword
    if firstTokenAfterAttributes != lastTokenOfName {
      before(firstTokenAfterAttributes, tokens: .open)
      after(lastTokenOfName, tokens: .close)
    }

    before(node.throwsOrRethrowsKeyword, tokens: .break)

    arrangeFunctionLikeDecl(
      node,
      attributes: node.attributes,
      genericWhereClause: node.genericWhereClause,
      body: node.body,
      bodyContentsKeyPath: \.statements)

    super.visit(node)
  }

  override func visit(_ node: DeinitializerDeclSyntax) {
    arrangeFunctionLikeDecl(
      node,
      attributes: node.attributes,
      genericWhereClause: nil,
      body: node.body,
      bodyContentsKeyPath: \.statements)
    super.visit(node)
  }

  override func visit(_ node: SubscriptDeclSyntax) {
    before(node.firstToken, tokens: .open)

    // Prioritize keeping "<modifiers> subscript" together.
    if let firstModifierToken = node.modifiers?.firstToken {
      before(firstModifierToken, tokens: .open)
      after(node.subscriptKeyword, tokens: .close)
    }

    arrangeAttributeList(node.attributes)

    if let genericWhereClause = node.genericWhereClause {
      before(genericWhereClause.firstToken, tokens: .break(.same), .open)
      after(genericWhereClause.lastToken, tokens: .close)
    }

    before(node.result.firstToken, tokens: .break)

    // The body of a subscript is an `AccessorBlockSyntax`; since we do the arrangement of the
    // braces and contents in the override for that node, we don't need to do them here.

    after(node.lastToken, tokens: .close)

    super.visit(node)
  }

  /// Applies formatting tokens to the tokens in the given function or function-like declaration
  /// node (e.g., initializers, deinitiailizers, and subscripts).
  private func arrangeFunctionLikeDecl<Node: BracedSyntax, BodyContents: Collection>(
    _ node: Syntax,
    attributes: AttributeListSyntax?,
    genericWhereClause: GenericWhereClauseSyntax?,
    body: Node?,
    bodyContentsKeyPath: KeyPath<Node, BodyContents>?
  ) where BodyContents.Element: Syntax {
    before(node.firstToken, tokens: .open)

    arrangeAttributeList(attributes)
    arrangeBracesAndContents(of: body, contentsKeyPath: bodyContentsKeyPath)

    if let genericWhereClause = genericWhereClause {
      before(genericWhereClause.firstToken, tokens: .break(.same), .open)
      after(body?.leftBrace ?? genericWhereClause.lastToken, tokens: .close)
    }

    after(node.lastToken, tokens: .close)
  }

  // MARK: - Property and subscript accessor block nodes

  override func visit(_ node: AccessorBlockSyntax) {
    arrangeBracesAndContents(of: node)
    super.visit(node)
  }

  override func visit(_ node: AccessorListSyntax) {
    for child in node.dropLast() {
      // If the child doesn't have a body (it's just the `get`/`set` keyword), then we're in a
      // protocol and we want to let them be placed on the same line if possible. Otherwise, we
      // place a newline between each accessor.
      after(child.lastToken, tokens: child.body == nil ? .break(.same) : .newline)
    }
    super.visit(node)
  }

  override func visit(_ node: AccessorDeclSyntax) {
    arrangeAttributeList(node.attributes)
    arrangeBracesAndContents(of: node.body, contentsKeyPath: \.statements)
    super.visit(node)
  }

  override func visit(_ node: AccessorParameterSyntax) {
    super.visit(node)
  }

  /// Returns a value indicating whether the body of the accessor block (regardless of whether it
  /// contains accessors or statements) is empty.
  private func isAccessorBlockEmpty(_ node: AccessorBlockSyntax?) -> Bool {
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

    arrangeBracesAndContents(of: node.body, contentsKeyPath: \.statements)

    before(node.elseKeyword, tokens: .newline)
    if node.elseBody is IfStmtSyntax {
      after(node.elseKeyword, tokens: .space)
    }

    arrangeBracesAndContents(of: node.elseBody as? CodeBlockSyntax, contentsKeyPath: \.statements)

    super.visit(node)
  }

  override func visit(_ node: GuardStmtSyntax) {
    after(node.guardKeyword, tokens: .break)
    before(node.elseKeyword, tokens: .break(.reset), .open)
    after(node.elseKeyword, tokens: .break)
    before(node.body.leftBrace, tokens: .close)

    arrangeBracesAndContents(
      of: node.body, contentsKeyPath: \.statements, shouldResetBeforeLeftBrace: false)

    super.visit(node)
  }

  override func visit(_ node: ForInStmtSyntax) {
    after(node.labelColon, tokens: .space)
    after(node.forKeyword, tokens: .space)
    before(node.inKeyword, tokens: .break)
    after(node.inKeyword, tokens: .space)

    arrangeBracesAndContents(of: node.body, contentsKeyPath: \.statements)

    super.visit(node)
  }

  override func visit(_ node: WhileStmtSyntax) {
    after(node.labelColon, tokens: .space)
    after(node.whileKeyword, tokens: .space)

    arrangeBracesAndContents(of: node.body, contentsKeyPath: \.statements)

    super.visit(node)
  }

  override func visit(_ node: RepeatWhileStmtSyntax) {
    arrangeBracesAndContents(of: node.body, contentsKeyPath: \.statements)

    before(node.whileKeyword, tokens: .break(.same))
    after(node.whileKeyword, tokens: .space)

    super.visit(node)
  }

  override func visit(_ node: DoStmtSyntax) {
    arrangeBracesAndContents(of: node.body, contentsKeyPath: \.statements)
    super.visit(node)
  }

  override func visit(_ node: CatchClauseSyntax) {
    before(node.catchKeyword, tokens: .newline)
    before(node.pattern?.firstToken, tokens: .break)

    arrangeBracesAndContents(of: node.body, contentsKeyPath: \.statements)

    super.visit(node)
  }

  override func visit(_ node: DeferStmtSyntax) {
    arrangeBracesAndContents(of: node.body, contentsKeyPath: \.statements)
    super.visit(node)
  }

  override func visit(_ node: BreakStmtSyntax) {
    before(node.label, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: ReturnStmtSyntax) {
    before(node.expression?.firstToken, tokens: .break)
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
    before(node.switchKeyword, tokens: .open)
    after(node.switchKeyword, tokens: .space)
    before(node.leftBrace, tokens: .break(.reset))
    after(node.leftBrace, tokens: .close)

    if !areBracesCompletelyEmpty(node, contentsKeyPath: \.cases) {
      before(node.rightBrace, tokens: .newline)
    } else {
      before(node.rightBrace, tokens: .break(.same, size: 0))
    }

    super.visit(node)
  }

  override func visit(_ node: SwitchCaseSyntax) {
    before(node.firstToken, tokens: .newline)
    after(node.label.lastToken, tokens: .break(.reset, size: 0), .break(.open), .open)
    after(node.lastToken, tokens: .break(.close, size: 0), .close)
    super.visit(node)
  }

  override func visit(_ node: SwitchCaseLabelSyntax) {
    before(node.caseKeyword, tokens: .open)
    after(node.caseKeyword, tokens: .space)
    after(node.colon, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: CaseItemSyntax) {
    before(node.firstToken, tokens: .open)
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
      after(node.operatorToken, tokens: .space)
    }
    super.visit(node)
  }

  override func visit(_ node: TupleExprSyntax) {
    after(node.leftParen, tokens: .break(.open, size: 0), .open)
    before(node.rightParen, tokens: .close, .break(.close, size: 0))
    super.visit(node)
  }

  override func visit(_ node: TupleElementListSyntax) {
    insertTokens(.break(.same), betweenElementsOf: node)
    super.visit(node)
  }

  override func visit(_ node: TupleElementSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.colon, tokens: .break)
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: ArrayExprSyntax) {
    after(node.leftSquare, tokens: .break(.open, size: 0), .open)
    before(node.rightSquare, tokens: .close, .break(.close, size: 0))
    super.visit(node)
  }

  override func visit(_ node: ArrayElementListSyntax) {
    insertTokens(.break(.same), betweenElementsOf: node)
    super.visit(node)
  }

  override func visit(_ node: ArrayElementSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: DictionaryExprSyntax) {
    after(node.leftSquare, tokens: .break(.open, size: 0), .open)
    before(node.rightSquare, tokens: .close, .break(.close, size: 0))
    super.visit(node)
  }

  override func visit(_ node: DictionaryElementListSyntax) {
    insertTokens(.break(.same), betweenElementsOf: node)
    super.visit(node)
  }

  override func visit(_ node: DictionaryTypeSyntax) {
    after(node.colon, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: DictionaryElementSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.colon, tokens: .break)
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: ImplicitMemberExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: MemberAccessExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: FunctionCallExprSyntax) {
    if node.argumentList.count == 1, node.argumentList[0].expression is ClosureExprSyntax {
      super.visit(node)
      return
    }

    if node.argumentList.count > 0 {
      // If there is a trailing closure, force the right parenthesis down to the next line so it
      // stays with the open curly brace.
      let breakBeforeRightParen = node.trailingClosure != nil

      after(node.leftParen, tokens: .break(.open, size: 0), .open)
      before(
        node.rightParen,
        tokens: .break(.close(mustBreak: breakBeforeRightParen), size: 0), .close)
    }
    before(node.trailingClosure?.leftBrace, tokens: .break(.reset))
    super.visit(node)
  }

  override func visit(_ node: FunctionCallArgumentSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.colon, tokens: .break)
    if let trailingComma = node.trailingComma {
      after(trailingComma, tokens: .close, .break(.same))
    } else {
      after(node.lastToken, tokens: .close)
    }
    super.visit(node)
  }

  override func visit(_ node: ClosureExprSyntax) {
    if let signature = node.signature {
      before(signature.firstToken, tokens: .break(.open))
      if node.statements.count > 0 {
        after(signature.inTok, tokens: .newline)
      } else {
        after(signature.inTok, tokens: .break(.same, size: 0))
      }
      before(node.rightBrace, tokens: .break(.close))
    } else {
      // Closures without signatures can have their contents laid out identically to any other
      // braced structure. The leading reset is skipped because the layout depends on whether it is
      // a trailing closure of a function call (in which case that function call supplies the reset)
      // or part of some other expression (where we want that expression's same/continue behavior to
      // apply).
      arrangeBracesAndContents(
        of: node, contentsKeyPath: \.statements, shouldResetBeforeLeftBrace: false)
    }
    super.visit(node)
  }

  override func visit(_ node: ClosureParamSyntax) {
    after(node.trailingComma, tokens: .break(.same))
    super.visit(node)
  }

  override func visit(_ node: ClosureSignatureSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.capture?.rightSquare, tokens: .break(.same))
    before(node.input?.firstToken, tokens: .open)
    after(node.input?.lastToken, tokens: .close)
    before(node.throwsTok, tokens: .break)
    before(node.output?.arrow, tokens: .break)
    after(node.lastToken, tokens: .close)
    before(node.inTok, tokens: .break(.same))
    super.visit(node)
  }

  override func visit(_ node: ClosureCaptureSignatureSyntax) {
    after(node.leftSquare, tokens: .break(.open, size: 0), .open)
    before(node.rightSquare, tokens: .break(.close, size: 0), .close)
    super.visit(node)
  }

  override func visit(_ node: ClosureCaptureItemSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.specifier?.lastToken, tokens: .break)
    before(node.assignToken, tokens: .break)
    after(node.assignToken, tokens: .break)
    if let trailingComma = node.trailingComma {
      before(trailingComma, tokens: .close)
      after(trailingComma, tokens: .break(.same))
    } else {
      after(node.lastToken, tokens: .close)
    }
    super.visit(node)
  }

  override func visit(_ node: SubscriptExprSyntax) {
    if node.argumentList.count > 0 {
      // If there is a trailing closure, force the right bracket down to the next line so it stays
      // with the open curly brace.
      let breakBeforeRightBracket = node.trailingClosure != nil

      after(node.leftBracket, tokens: .break(.open, size: 0), .open)
      before(
        node.rightBracket,
        tokens: .break(.close(mustBreak: breakBeforeRightBracket), size: 0), .close)
    }
    before(node.trailingClosure?.leftBrace, tokens: .space)
    super.visit(node)
  }

  override func visit(_ node: ExpressionSegmentSyntax) {
    // TODO: For now, just use the raw text of the node and don't try to format it deeper. In the
    // future, we should find a way to format the expression but without wrapping so that at least
    // internal whitespace is fixed.
    appendToken(.syntax(node.description))
    // Call to super.visit is not needed here.
  }

  override func visit(_ node: ObjcKeyPathExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: AssignmentExprSyntax) {
    before(node.assignToken, tokens: .break)
    after(node.assignToken, tokens: .space)
    super.visit(node)
  }

  override func visit(_ node: ObjectLiteralExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: ParameterClauseSyntax) {
    after(node.leftParen, tokens: .break(.open, size: 0), .open)
    before(node.rightParen, tokens: .break(.close, size: 0), .close)
    super.visit(node)
  }

  override func visit(_ node: FunctionParameterSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.colon, tokens: .break)
    before(node.secondName, tokens: .break)

    if let trailingComma = node.trailingCommaWorkaround {
      after(trailingComma, tokens: .close, .break(.same))
    } else {
      after(node.lastToken, tokens: .close)
    }
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
      after(node.poundKeyword, tokens: .space)
    case .poundElseKeyword:
      break
    default:
      preconditionFailure()
    }

    // Unlike other code blocks, where we may want a single statement to be laid out on the same
    // line as a parent construct, the content of an `#if` block must always be on its own line;
    // the newline token inserted at the end enforces this.
    before(node.elements.firstToken, tokens: .break(.open), .open)
    after(node.elements.lastToken, tokens: .break(.close), .newline, .close)
    super.visit(node)
  }

  override func visit(_ node: MemberDeclBlockSyntax) {
    insertTokens(.break(.reset, size: 0), .newline, betweenElementsOf: node.members)
    super.visit(node)
  }

  override func visit(_ node: SourceFileSyntax) {
    before(node.eofToken, tokens: .newline)
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
    after(node.trailingComma, tokens: .break)
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
    super.visit(node)
  }

  override func visit(_ node: CodeBlockItemListSyntax) {
    insertTokens(.break(.reset, size: 0), .newline, betweenElementsOf: node)
    super.visit(node)
  }

  override func visit(_ node: CodeBlockItemSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: GenericParameterClauseSyntax) {
    after(node.leftAngleBracket, tokens: .break(.open, size: 0), .open)
    before(node.rightAngleBracket, tokens: .break(.close, size: 0), .close)
    super.visit(node)
  }

  override func visit(_ node: ArrayTypeSyntax) {
    super.visit(node)
  }

  override func visit(_ node: TupleTypeSyntax) {
    before(node.leftParen, tokens: .open)
    after(node.leftParen, tokens: .break(.open, size: 0), .open)
    before(node.rightParen, tokens: .break(.close, size: 0), .close)
    after(node.rightParen, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: TupleTypeElementSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.colon, tokens: .break)
    before(node.secondNameWorkaround, tokens: .break)

    if let trailingComma = node.trailingCommaWorkaround {
      after(trailingComma, tokens: .close, .break(.same))
    } else {
      after(node.lastToken, tokens: .close)
    }
    super.visit(node)
  }

  override func visit(_ node: FunctionTypeSyntax) {
    after(node.leftParen, tokens: .break(.open, size: 0), .open)
    before(node.rightParen, tokens: .break(.close, size: 0), .close)
    before(node.throwsOrRethrowsKeyword, tokens: .break)
    before(node.arrow, tokens: .break)
    before(node.returnType.firstToken, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: GenericArgumentClauseSyntax) {
    after(node.leftAngleBracket, tokens: .break(.open, size: 0), .open)
    before(node.rightAngleBracket, tokens: .break(.close, size: 0), .close)
    super.visit(node)
  }

  override func visit(_ node: TuplePatternSyntax) {
    after(node.leftParen, tokens: .break(.open, size: 0), .open)
    before(node.rightParen, tokens: .break(.close, size: 0), .close)
    super.visit(node)
  }

  override func visit(_ node: AsExprSyntax) {
    before(node.asTok, tokens: .break)
    before(node.typeName.firstToken, tokens: .space)
    super.visit(node)
  }

  override func visit(_ node: IsExprSyntax) {
    before(node.isTok, tokens: .break)
    before(node.typeName.firstToken, tokens: .space)
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
    after(node.arrowToken, tokens: .space)
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
    after(node.attributes?.lastToken, tokens: .space)
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
    before(node.questionMark, tokens: .break(.open), .open)
    after(node.questionMark, tokens: .space)
    before(node.colonMark, tokens: .break(.same))
    after(node.colonMark, tokens: .space)
    after(node.secondChoice.lastToken, tokens: .break(.close, size: 0), .close)
    super.visit(node)
  }

  override func visit(_ node: WhereClauseSyntax) {
    before(node.whereKeyword, tokens: .break(.same), .open)
    after(node.whereKeyword, tokens: .break)
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
    super.visit(node)
  }

  override func visit(_ node: SuperRefExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: VariableDeclSyntax) {
    arrangeAttributeList(node.attributes)
    after(node.letOrVarKeyword, tokens: .space)
    super.visit(node)
  }

  override func visit(_ node: AsTypePatternSyntax) {
    super.visit(node)
  }

  override func visit(_ node: InheritedTypeSyntax) {
    after(node.trailingComma, tokens: .break(.same))
    super.visit(node)
  }

  override func visit(_ node: IsTypePatternSyntax) {
    after(node.isKeyword, tokens: .space)
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
    arrangeAttributeList(node.attributes)

    after(node.typealiasKeyword, tokens: .break)

    if let genericWhereClause = node.genericWhereClause {
      before(genericWhereClause.firstToken, tokens: .break(.same), .open)
      after(node.lastToken, tokens: .close)
    }
    super.visit(node)
  }

  override func visit(_ node: TypeInitializerClauseSyntax) {
    before(node.equal, tokens: .break)
    after(node.equal, tokens: .space)
    super.visit(node)
  }

  override func visit(_ node: AttributedTypeSyntax) {
    arrangeAttributeList(node.attributes)
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
    super.visit(node)
  }

  override func visit(_ node: PoundErrorDeclSyntax) {
    super.visit(node)
  }

  override func visit(_ node: SpecializeExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: TypeAnnotationSyntax) {
    after(node.colon, tokens: .break)
    super.visit(node)
  }

  override func visit(_ node: UnknownPatternSyntax) {
    super.visit(node)
  }

  override func visit(_ node: CompositionTypeSyntax) {
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
      after(trailingComma, tokens: .close, .break(.same))
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
      after(trailingComma, tokens: .close, .break(.same))
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
    after(node.equal, tokens: .space)
    super.visit(node)
  }

  override func visit(_ node: PoundFunctionExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: StringLiteralExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: AssociatedtypeDeclSyntax) {
    arrangeAttributeList(node.attributes)

    after(node.associatedtypeKeyword, tokens: .break)

    if let genericWhereClause = node.genericWhereClause {
      before(genericWhereClause.firstToken, tokens: .break(.same), .open)
      after(node.lastToken, tokens: .close)
    }
    super.visit(node)
  }

  override func visit(_ node: BooleanLiteralExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: ElseIfContinuationSyntax) {
    super.visit(node)
  }

  override func visit(_ node: GenericWhereClauseSyntax) {
    after(node.whereKeyword, tokens: .break(.open))
    after(node.lastToken, tokens: .break(.close, size: 0))
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
    after(node.equalityToken, tokens: .space)
    if let trailingComma = node.trailingComma {
      after(trailingComma, tokens: .close, .break(.same))
    } else {
      after(node.lastToken, tokens: .close)
    }
    super.visit(node)
  }

  override func visit(_ node: TuplePatternElementSyntax) {
    after(node.trailingComma, tokens: .break(.same))
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
    after(node.colon, tokens: .break(.open, size: 1))
    before(node.inheritedTypeCollection.firstToken, tokens: .open)
    after(node.inheritedTypeCollection.lastToken, tokens: .close)
    after(node.lastToken, tokens: .break(.close, size: 0))
    super.visit(node)
  }

  override func visit(_ node: UnresolvedPatternExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: CompositionTypeElementSyntax) {
    before(node.ampersand, tokens: .break)
    after(node.ampersand, tokens: .space)
    super.visit(node)
  }

  override func visit(_ node: ConformanceRequirementSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.colon, tokens: .break)

    if let trailingComma = node.trailingComma {
      after(trailingComma, tokens: .close, .break(.same))
    } else {
      after(node.lastToken, tokens: .close)
    }

    super.visit(node)
  }

  override func visit(_ node: StringInterpolationExprSyntax) {
    super.visit(node)
  }

  override func visit(_ node: MatchingPatternConditionSyntax) {
    before(node.firstToken, tokens: .open)
    after(node.caseKeyword, tokens: .break)
    after(node.lastToken, tokens: .close)
    super.visit(node)
  }

  override func visit(_ node: OptionalBindingConditionSyntax) {
    before(node.firstToken, tokens: .open)
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
    if let before = beforeMap[token] {
      before.forEach(appendToken)
    }

    let text: String
    if token.leadingTrivia.hasBackticks && token.trailingTrivia.hasBackticks {
      text = "`\(token.text)`"
    } else {
      text = token.text
    }
    appendToken(.syntax(text))

    extractTrailingComment(token)
    if let afterGroups = afterMap[token] {
      for after in afterGroups.reversed() {
        after.forEach(appendToken)
      }
    }
  }

  // MARK: - Various other helper methods

  /// Applies formatting tokens around and between the attributes in an attribute list.
  private func arrangeAttributeList(_ attributes: AttributeListSyntax?) {
    if let attributes = attributes {
      before(attributes.firstToken, tokens: .open)
      insertTokens(.break(.same), betweenElementsOf: attributes)
      after(attributes.lastToken, tokens: .close, .break(.same))
    }
  }

  /// Returns a value indicating whether or not the given braced syntax node is completely empty;
  /// that is, it contains neither child syntax nodes (aside from the braces) *nor* any comments.
  ///
  /// Checking for comments separately is vitally important, because a code block that appears to be
  /// "empty" because it doesn't contain any statements might still contain comments, and if those
  /// are line comments, we need to make sure to insert the same breaks that we would if there were
  /// other statements there to get the same layout.
  ///
  /// Note the slightly different generic constraints on this and the other overloads. All are
  /// required because protocols in Swift do not conform to themselves, so if the element type of
  /// the collection is *precisely* `Syntax`, the constraint `BodyContents.Element: Syntax` is not
  /// satisfied and we must constrain it by `BodyContents.Element == Syntax` instead.
  ///
  /// - Parameters:
  ///   - node: A node that conforms to `BracedSyntax`.
  ///   - contentsKeyPath: A keypath describing how to get from `node` to the contents of the node
  ///     (a `Collection` whose elements are of a type that conforms to `Syntax`).
  /// - Returns: True if the collection at the node's keypath is empty and there are no comments.
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
  /// - Parameters:
  ///   - node: A node that conforms to `BracedSyntax`.
  ///   - contentsKeyPath: A keypath describing how to get from `node` to the contents of the node
  ///     (a `Collection` whose elements are of type `Syntax`).
  /// - Returns: True if the collection at the node's keypath is empty and there are no comments.
  private func areBracesCompletelyEmpty<Node: BracedSyntax, BodyContents: Collection>(
    _ node: Node,
    contentsKeyPath: KeyPath<Node, BodyContents>
  ) -> Bool where BodyContents.Element == Syntax {
    // If the collection is empty, then any comments that might be present in the block must be
    // leading trivia of the right brace.
    let commentPrecedesRightBrace = node.rightBrace.leadingTrivia.numberOfComments > 0
    return node[keyPath: contentsKeyPath].isEmpty && !commentPrecedesRightBrace
  }

  /// Returns a value indicating whether or not the given braced syntax node is completely empty;
  /// that is, it contains neither child syntax nodes (aside from the braces) *nor* any comments.
  ///
  /// - Parameters:
  ///   - node: A node that conforms to `BracedSyntax`.
  ///   - contentsKeyPath: A keypath describing how to get from `node` to the contents of the node
  ///     (a `Collection` whose elements are of type `DeclSyntax`).
  /// - Returns: True if the collection at the node's keypath is empty and there are no comments.
  private func areBracesCompletelyEmpty<Node: BracedSyntax, BodyContents: Collection>(
    _ node: Node,
    contentsKeyPath: KeyPath<Node, BodyContents>
  ) -> Bool where BodyContents.Element == DeclSyntax {
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
  ///     (a `Collection` whose elements are of a type that conforms to `Syntax`).
  ///   - shouldResetBeforeLeftBrace: If true, a `reset` break will be inserted before the node's
  ///     left brace (the default behavior). Passing false will suppress this break, which is useful
  ///     if you have already placed a `reset` elsewhere (for example, in a `guard` statement, the
  ///     `reset` is inserted before the `else` keyword to force both it and the brace down to the
  ///     next line).
  private func arrangeBracesAndContents<Node: BracedSyntax, BodyContents: Collection>(
    of node: Node?,
    contentsKeyPath: KeyPath<Node, BodyContents>?,
    shouldResetBeforeLeftBrace: Bool = true
  ) where BodyContents.Element: Syntax {
    guard let node = node, let contentsKeyPath = contentsKeyPath else { return }

    if shouldResetBeforeLeftBrace {
      before(node.leftBrace, tokens: .break(.reset, size: 1))
    }
    if !areBracesCompletelyEmpty(node, contentsKeyPath: contentsKeyPath) {
      after(node.leftBrace, tokens: .break(.open, size: 1), .open)
      before(node.rightBrace, tokens: .break(.close, size: 1), .close)
    } else {
      before(node.rightBrace, tokens: .break(.same, size: 0))
    }
  }

  /// Applies consistent formatting to the braces and contents of the given node.
  ///
  /// - Parameters:
  ///   - node: A node that conforms to `BracedSyntax`.
  ///   - contentsKeyPath: A keypath describing how to get from `node` to the contents of the node
  ///     (a `Collection` whose elements are of type `Syntax`).
  ///   - shouldResetBeforeLeftBrace: If true, a `reset` break will be inserted before the node's
  ///     left brace (the default behavior). Passing false will suppress this break, which is useful
  ///     if you have already placed a `reset` elsewhere (for example, in a `guard` statement, the
  ///     `reset` is inserted before the `else` keyword to force both it and the brace down to the
  ///     next line).
  private func arrangeBracesAndContents<Node: BracedSyntax, BodyContents: Collection>(
    of node: Node?,
    contentsKeyPath: KeyPath<Node, BodyContents>?,
    shouldResetBeforeLeftBrace: Bool = true
  ) where BodyContents.Element == Syntax {
    guard let node = node, let contentsKeyPath = contentsKeyPath else { return }

    if shouldResetBeforeLeftBrace {
      before(node.leftBrace, tokens: .break(.reset, size: 1))
    }
    if !areBracesCompletelyEmpty(node, contentsKeyPath: contentsKeyPath) {
      after(node.leftBrace, tokens: .break(.open, size: 1), .open)
      before(node.rightBrace, tokens: .break(.close, size: 1), .close)
    } else {
      before(node.rightBrace, tokens: .break(.same, size: 0))
    }
  }

  /// Applies consistent formatting to the braces and contents of the given node.
  ///
  /// - Parameters:
  ///   - node: A node that conforms to `BracedSyntax`.
  ///   - contentsKeyPath: A keypath describing how to get from `node` to the contents of the node
  ///     (a `Collection` whose elements are of type `DeclSyntax`).
  ///   - shouldResetBeforeLeftBrace: If true, a `reset` break will be inserted before the node's
  ///     left brace (the default behavior). Passing false will suppress this break, which is useful
  ///     if you have already placed a `reset` elsewhere (for example, in a `guard` statement, the
  ///     `reset` is inserted before the `else` keyword to force both it and the brace down to the
  ///     next line).
  private func arrangeBracesAndContents<Node: BracedSyntax, BodyContents: Collection>(
    of node: Node?,
    contentsKeyPath: KeyPath<Node, BodyContents>?,
    shouldResetBeforeLeftBrace: Bool = true
  ) where BodyContents.Element == DeclSyntax {
    guard let node = node, let contentsKeyPath = contentsKeyPath else { return }

    if shouldResetBeforeLeftBrace {
      before(node.leftBrace, tokens: .break(.reset, size: 1))
    }
    if !areBracesCompletelyEmpty(node, contentsKeyPath: contentsKeyPath) {
      after(node.leftBrace, tokens: .break(.open, size: 1), .open)
      before(node.rightBrace, tokens: .break(.close, size: 1), .close)
    } else {
      before(node.rightBrace, tokens: .break(.same, size: 0))
    }
  }

  /// Applies consistent formatting to the braces and contents of the given node.
  ///
  /// - Parameter node: An `AccessorBlockSyntax` node.
  private func arrangeBracesAndContents(of node: AccessorBlockSyntax) {
    // If the collection is empty, then any comments that might be present in the block must be
    // leading trivia of the right brace.
    let commentPrecedesRightBrace = node.rightBrace.leadingTrivia.numberOfComments > 0
    let bracesAreCompletelyEmpty = isAccessorBlockEmpty(node) && !commentPrecedesRightBrace

    before(node.leftBrace, tokens: .break(.reset, size: 1))

    if !bracesAreCompletelyEmpty {
      after(node.leftBrace, tokens: .break(.open, size: 1), .open)
      before(node.rightBrace, tokens: .break(.close, size: 1), .close)
    } else {
      before(node.rightBrace, tokens: .break(.same, size: 0))
    }
  }

  private func extractTrailingComment(_ token: TokenSyntax) {
    let nextToken = token.nextToken
    guard let trivia = nextToken?.leadingTrivia,
          let firstPiece = trivia[safe: 0] else {
      return
    }

    let position = token.endPositionAfterTrailingTrivia
    switch firstPiece {
    case .lineComment(let text):
      appendToken(.space(size: 2))
      appendToken(
        .comment(Comment(kind: .line, text: text, position: position), wasEndOfLine: true))
      appendToken(.newline)
    case .blockComment(let text):
      appendToken(.space(size: 1))
      appendToken(
        .comment(Comment(kind: .block, text: text, position: position), wasEndOfLine: false))
      // We place a size-0 break after the comment to allow a discretionary newline after the
      // comment if the user places one here but the comment is otherwise adjacent to a text token.
      appendToken(.break(.same, size: 0))
    default:
      return
    }
  }

  private func extractLeadingTrivia(_ token: TokenSyntax) {
    let isStartOfFile = token.previousToken == nil
    let trivia = token.leadingTrivia

    for (index, piece) in trivia.enumerated() {
      switch piece {
      case .lineComment(let text):
        if index > 0 || isStartOfFile {
          appendToken(.comment(Comment(kind: .line, text: text), wasEndOfLine: false))
          appendToken(.newline)
        }

      case .blockComment(let text):
        if index > 0 || isStartOfFile {
          appendToken(.comment(Comment(kind: .block, text: text), wasEndOfLine: false))
          // We place a size-0 break after the comment to allow a discretionary newline after the
          // comment if the user places one here but the comment is otherwise adjacent to a text
          // token.
          appendToken(.break(.same, size: 0))
        }

      case .docLineComment(let text):
        appendToken(.comment(Comment(kind: .docLine, text: text), wasEndOfLine: false))
        appendToken(.newline)

      case .docBlockComment(let text):
        appendToken(.comment(Comment(kind: .docBlock, text: text), wasEndOfLine: false))
        appendToken(.newline)

      case .newlines(let count), .carriageReturns(let count), .carriageReturnLineFeeds(let count):
        if config.respectsExistingLineBreaks && isDiscretionaryNewlineAllowed(before: token) {
          appendToken(.newlines(count, discretionary: true))
        }
        else {
          // Even if discretionary line breaks are not being respected, we still respect multiple
          // line breaks in order to keep blank separator lines that the user might want.
          // TODO: It would be nice to restrict this to only allow multiple lines between statements
          // and declarations; as currently implemented, multiple newlines will locally override the
          // configuration setting.
          if count > 1 {
            appendToken(.newlines(count, discretionary: true))
          }
        }

      default:
        break
      }
    }
  }

  /// Returns a value indicating whether or not discretionary newlines are permitted before the
  /// given syntax token.
  ///
  /// Discretionary newlines are allowed before any token that is preceded by a break or an existing
  /// newline (ignoring open/close group tokens, which do not contribute to this). In other words,
  /// this means that users may insert their own breaks in places where the pretty printer allows
  /// them, even if those breaks wouldn't cause wrapping based on the column limit, but they may not
  /// place them in places where the pretty printer would not break (for example, at a space token
  /// that is intended to keep two tokens glued together).
  private func isDiscretionaryNewlineAllowed(before token: TokenSyntax) -> Bool {
    func isBreakMoreRecentThanNonbreakingContent(_ tokens: [Token]) -> Bool? {
      for token in tokens.reversed() as ReversedCollection {
        switch token {
        case .break, .newlines: return true
        case .comment, .space, .syntax, .verbatim: return false
        default: break
        }
      }
      return nil
    }

    // First, check the pretty printer tokens that will be added before the text token. If we find
    // a break or newline before we find some other text, we allow a discretionary newline. If we
    // find some other content, we don't allow it.
    //
    // If there were no before tokens, then we do the same check the token stream created thus far,
    // returning true if there were no tokens at all in the stream (which would mean there was a
    // discretionary newline at the beginning of the file).
    if let beforeTokens = beforeMap[token],
      let foundBreakFirst = isBreakMoreRecentThanNonbreakingContent(beforeTokens)
    {
      return foundBreakFirst
    }
    return isBreakMoreRecentThanNonbreakingContent(tokens) ?? true
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

      // If we see a pair of newlines where one is required and one is not, keep only the required
      // one.
      case (.newlines(_, discretionary: false), .newlines(let count, discretionary: true)),
        (.newlines(let count, discretionary: true), .newlines(_, discretionary: false)):
        tokens[tokens.count - 1] = .newlines(count, discretionary: true)
        return

      // If we see two neighboring pairs of required newlines, combine them into a new token with
      // the sum of their counts.
      case (.newlines(let first, discretionary: true), .newlines(let second, discretionary: true)):
        tokens[tokens.count - 1] = .newlines(first + second, discretionary: true)
        return

      // If we see two neighboring pairs of non-required newlines, keep only the larger one.
      case (
        .newlines(let first, discretionary: false),
        .newlines(let second, discretionary: false)
      ):
        tokens[tokens.count - 1] = .newlines(max(first, second), discretionary: true)
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
