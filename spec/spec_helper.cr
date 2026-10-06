require "spec"
require "../src/compilation_error"
require "../src/ast_data/*"
require "../src/types/*"
require "../src/environment/*"
require "../src/parsing/*"
require "../src/type_checking/*"
require "../src/codegen/*"

def source_location(l : Int = 0, c : Int = 0)
  AST::SourceLocation.new(l, c)
end

def parse(source : String)
  DoisC::Parsing::Parser.new(source).parse
end

def expect_parse_error(source : String)
  expect_raises(DoisC::Parsing::ParseError) { parse(source) }
end

def check(source : String)
  ast = parse(source)
  DoisC::TypeChecking::TypeChecker.new.check(ast)
  ast
end

# unwraps ast into single main procedure (likely to be changed)
def unwrap_main(ast : DoisC::ASTData::AST) : DoisC::ASTData::Procedure

  main_decl = ast.module_decl.body.find do |s|
    s.is_a?(DoisC::ASTData::ProcedureDeclaration) && s.name == "main"
  end.as(DoisC::ASTData::ProcedureDeclaration)
  main_decl.body
end

# unwraps ast procedure's last statement with single expression statement in it as an expression
# (unwraps last so previous lines are for environment setup)
def unwrap_expr_stmt(ast : DoisC::ASTData::AST) : DoisC::ASTData::Expression
  unwrap_main(ast).statements.last.as(AST::ExpressionStatement).expression
end

def expect_type_error(source : String)
  expect_raises(DoisC::TypeChecking::TypeError) { check(source) }
end

def walk_expressions(expression : AST::Expression, &block : AST::Expression ->)
  # Depth-first traversal over all expressions
  block.call(expression)

  case expression
  when AST::BinaryExpression
    walk_expressions(expression.left, &block)
    walk_expressions(expression.right, &block)
  when AST::UnaryExpression
    walk_expressions(expression.right, &block)
  when AST::IfExpression
    expression.branches.each do |branch|
      walk_expressions(branch.condition, &block)
      walk_expressions(branch.body, &block)
    end
    if body = expression.else_body
      walk_expressions(body, &block)
    end
  when AST::MatchExpression
    walk_expressions(expression.scrutinee, &block)
    expression.branches.each do |c|
      walk_expressions(c.body, &block)
    end
  when AST::NamedArgument
    walk_expressions(expression.value, &block)
  when AST::Call
    expression.arguments.each do |arg|
      walk_expressions(arg, &block)
    end

  # literals, identifiers, etc → no children
  end
end

def compile_to_c(source : String) : String
  ast = check(source)
  DoisC::Codegen::Transpiler.new(IO::Memory.new).transpile(ast)
end

def compile_and_run_c(source : String) : String
  c_source = compile_to_c(source)

  repo_root = File.expand_path("..", __DIR__)
  out_c_path = File.join(repo_root, "out.c")
  binary_path = File.join(repo_root, "out")

  begin
    File.write(out_c_path, c_source)

    compile_output = IO::Memory.new
    compile_status = Process.run(
      "cc",
      ["out.c", "-o", "out", "./src/codegen/runtime/runtime.c"],
      chdir: repo_root,
      output: compile_output,
      error: compile_output,
    )

    unless compile_status.success?
      raise "C compilation failed for generated output:\n#{compile_output.to_s}"
    end

    io = IO::Memory.new
    run_status = Process.run(
      binary_path,
      chdir: repo_root,
      output: io,
      error: io,
    )

    unless run_status.success?
      raise "Generated binary exited unsuccessfully:\n#{io.to_s}"
    end

    io.to_s
  ensure
    File.delete(out_c_path) if File.exists?(out_c_path)
    File.delete(binary_path) if File.exists?(binary_path)
  end
end


alias TE = DoisC::TypeChecking::TypeEngine
alias G = DoisC::Environment::Global
alias VC = DoisC::Environment::VerificationContext
alias AST = DoisC::ASTData
alias T = DoisC::Types
