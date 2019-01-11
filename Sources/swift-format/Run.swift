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

import Foundation
import SwiftFormatConfiguration
import SwiftFormatCore
import SwiftFormatRules
import SwiftFormatPrettyPrint
import SwiftSyntax

/// Runs the linting pipeline over the provided source file.
///
/// If there were any lint diagnostics emitted, this function returns a non-zero exit code.
/// - Parameter path: The absolute path to the source file to be linted.
/// - Returns: Zero if there were no lint errors, otherwise a non-zero number.
public func lintMain(path: String) -> Int {
  let url = URL(fileURLWithPath: path)
  let engine = makeDiagnosticEngine()

  let context = Context(
    configuration: Configuration(),
    diagnosticEngine: engine,
    fileURL: url
  )

  let pipeline = LintPipeline(context: context)
  populate(pipeline)

  do {
    let file = try SyntaxTreeParser.parse(url)

    // Important! We need to cast this to Syntax to avoid going directly into the specialized
    // version of visit(_: SourceFileSyntax), which will not run the pipeline properly.
    pipeline.visit(file as Syntax)
  } catch {
    fatalError("\(error)")
  }
  return engine.diagnostics.isEmpty ? 0 : 1
}

/// Runs the formatting pipeline over the provided source file.
///
/// - Parameter path: The absolute path to the source file to be linted.
/// - Returns: Zero if there were no lint errors, otherwise a non-zero number.
public func formatMain(path: String, isDebugMode: Bool, prettyPrint: Bool, printTokenStream: Bool) -> Int {
  let url = URL(fileURLWithPath: path)
  let configuration = Configuration()
  let context = Context(configuration: configuration, diagnosticEngine: nil, fileURL: url)

  let pipeline = FormatPipeline(context: context)
  populate(pipeline)
  do {
    let file = try SyntaxTreeParser.parse(url)

    // Important! We need to cast this to Syntax to avoid going directly into the specialized
    // version of visit(_: SourceFileSyntax), which will not run the pipeline properly.
    let formatted = pipeline.visit(file as Syntax)

    if prettyPrint {
      // We create a different context here because we only want diagnostics from the pretty printer
      // phase when formatting.
      let prettyPrintContext = Context(
        configuration: configuration,
        diagnosticEngine: makeDiagnosticEngine(),
        fileURL: url)

      let printer = PrettyPrinter(
        context: prettyPrintContext,
        node: formatted,
        isDebugMode: isDebugMode,
        printTokenStream: printTokenStream
      )
      print(printer.prettyPrint(), terminator: "")
    } else {
      print(formatted.description, terminator: "")
    }
  } catch {
    fatalError("\(error)")
  }
  return 0
}

/// Makes and returns a new configured diagnostic engine.
private func makeDiagnosticEngine() -> DiagnosticEngine {
  let engine = DiagnosticEngine()
  let consumer = PrintingDiagnosticConsumer()
  engine.addConsumer(consumer)
  return engine
}
