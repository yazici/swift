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

import Basic
import Foundation
import SwiftFormatConfiguration
import SwiftFormatCore
import SwiftFormatPrettyPrint
import Utility

enum Mode: String, Codable, ArgumentKind {
  case format
  case lint
  case dumpConfiguration = "dump-configuration"
  case version

  static var completion: ShellCompletion {
    return .values([
      ("format", "Format the provided files."),
      ("lint", "Lint the provided files."),
      ("dump-configuration", "Dump the default configuration as JSON to standard output."),
    ])
  }

  init(argument: String) throws {
    guard let mode = Mode(rawValue: argument) else {
      throw ArgumentParserError.invalidValue(argument: argument, error: .unknown(value: argument))
    }
    self = mode
  }
}

struct CommandLineOptions: Codable {
  var configurationPath: String? = nil
  var paths: [String] = []
  var verboseLevel = 0
  var mode: Mode = .format
  var prettyPrint: Bool = false
  var printTokenStream: Bool = false
}

func processArguments(commandName: String, _ arguments: [String]) -> CommandLineOptions {
  let parser = ArgumentParser(commandName: commandName,
                              usage: "[options] <filename or path> ...",
                              overview: "Format or lint Swift source code.")
  let binder = ArgumentBinder<CommandLineOptions>()
  binder.bind(
    option: parser.add(
      option: "--mode",
      shortName: "-m",
      kind: Mode.self,
      usage: "The mode to run swift-format in. Either 'format', 'lint', or 'dump-configuration'."
  )) {
    $0.mode = $1
  }
  binder.bind(
    option: parser.add(
      option: "--version",
      shortName: "-v",
      kind: Bool.self,
      usage: "Prints the version and exists"
  )) { opts, _ in
    opts.mode = .version
  }
  binder.bindArray(
    positional: parser.add(
      positional: "filenames or paths",
      kind: [String].self,
      optional: true,
      strategy: .upToNextOption,
      usage: "One or more input filenames",
      completion: .filename
  )) {
    $0.paths = $1
  }
  binder.bind(
    option: parser.add(
      option: "--pretty-print",
      shortName: "-p",
      kind: Bool.self,
      usage: "Pretty-print the output and automatically apply line-wrapping."
  )) {
    $0.prettyPrint = $1
  }
  binder.bind(
    option: parser.add(
      option: "--token-stream",
      kind: Bool.self,
      usage: "Print out the pretty-printer token stream."
  )) {
    $0.printTokenStream = $1
  }
  binder.bind(
    option: parser.add(
      option: "--configuration",
      kind: String.self,
      usage: "The path to a JSON file containing the configuration of the linter/formatter."
  )) {
    $0.configurationPath = $1
  }

  var opts = CommandLineOptions()
  do {
    let args = try parser.parse(arguments)
    binder.fill(args, into: &opts)
  } catch {
    stderrStream.write("error: \(error)\n\n")
    parser.printUsage(on: stderrStream)
    exit(1)
  }
  return opts
}

func main(_ arguments: [String]) -> Int32 {
  let url = URL(fileURLWithPath: arguments.first!)
  let options = processArguments(commandName: url.lastPathComponent, Array(arguments.dropFirst()))
  switch options.mode {
  case .format:
    var ret = 0
    let configuration = decodedConfiguration(fromFileAtPath: options.configurationPath)
    for path in options.paths {
      ret |= formatMain(
        configuration: configuration,
        path: path,
        prettyPrint: options.prettyPrint,
        printTokenStream: options.printTokenStream
      )
    }
    return Int32(ret)
  case .lint:
    var ret = 0
    let configuration = decodedConfiguration(fromFileAtPath: options.configurationPath)
    for path in options.paths {
      ret |= lintMain(configuration: configuration, path: path)
    }
    return Int32(ret)
  case .dumpConfiguration:
    dumpDefaultConfiguration()
    return 0
  case .version:
    print("0.0.1") // TODO(abl): Something fancy based on the git hash
    return 0
  }
}

/// Loads and returns a `Configuration` from the given JSON file if it is found and is valid. If the
/// file does not exist or there was an error decoding it, the program exits with a non-zero exit
/// code.
private func decodedConfiguration(fromFileAtPath path: String?) -> Configuration {
  if let path = path {
    do {
      let url = URL(fileURLWithPath: path)
      let data = try Data(contentsOf: url)
      return try JSONDecoder().decode(Configuration.self, from: data)
    }
    catch {
      // TODO: Improve error message, write to stderr.
      print("Could not load configuration at \(path): \(error)")
      exit(1)
    }
  }
  else {
    return Configuration()
  }
}

/// Dumps the default configuration as JSON to standard output.
private func dumpDefaultConfiguration() {
  let configuration = Configuration()
  do {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    if #available(macOS 10.13, *) {
      encoder.outputFormatting.insert(.sortedKeys)
    }

    let data = try encoder.encode(configuration)
    guard let jsonString = String(data: data, encoding: .utf8) else {
      // This should never happen, but let's make sure we fail more gracefully than crashing, just
      // in case.
      // TODO: Improve error message, write to stderr.
      print("Could not dump the default configuration: the JSON was not valid UTF-8")
      exit(1)
    }
    print(jsonString)
  }
  catch {
    // TODO: Improve error message, write to stderr.
    print("Could not dump the default configuration: \(error)")
    exit(1)
  }
}

exit(main(CommandLine.arguments))
