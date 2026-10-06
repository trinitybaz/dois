# require "../spec_helper"

# describe DoisC::Parsing do
#   it "parses a simple let binding" do
#     ast = parse <<-DOIS
#       let x = 2;
#     DOIS
#     stmt = ast.procedure.statements.first
#     stmt.should be_a(AST::Binding)
#   end
#   it "parses a simple var assignment" do
#     ast = parse <<-DOIS
#       var x = 3;
#     DOIS
#     stmt = ast.procedure.statements.first
#     stmt.should be_a(AST::VarDeclaration)
#   end
#   it "parses a simple type annotation" do
#     ast = parse <<-DOIS
#       let x : Int = 2;
#     DOIS
#     stmt = ast.procedure.statements.first
#     stmt.as(AST::Binding).type_id.should_not be_nil
#   end

#   it "fails on invalid let binding" do
#     expect_parse_error <<-DOIS
#       let x = ;
#     DOIS
#   end

#   it "fails on missing semicolon" do
#     expect_parse_error <<-DOIS
#       let x = 5
#     DOIS
#   end

#   it "parses binary expressions" do
#     ast = parse("let x = 1 + 2;")
#     stmt = ast.procedure.statements.first
#     stmt.should be_a(AST::Binding)
#   end

#   it "parses nested expressions" do
#     ast = parse("let x = (1 + 2) * 3;")
#     stmt = ast.procedure.statements.first
#     stmt.should be_a(AST::Binding)
#   end

#   it "parses function declarations" do
#     ast = parse <<-DOIS
#       fn add $ (a : Int, b : Int) : Int =>
#         a + b
#       end
#     DOIS
#     stmt = ast.procedure.statements.first
#     stmt.should be_a(AST::FunctionDeclaration)
#   end

#   it "parses constructor calls" do
#     ast = parse("let x = Some(value = 5);")
#     stmt = ast.procedure.statements.first
#     stmt.should be_a(AST::Binding)
#   end

#   it "parses match expressions" do
#     ast = parse <<-DOIS
#       match x then
#         Nil => 0
#       end;
#     DOIS
#     stmt = ast.procedure.statements.first
#     stmt.should_not be_nil
#   end

#   it "parses multiple statements" do
#     ast = parse <<-DOIS
#       let x = 1;
#       let y = 2;
#     DOIS
#     ast.procedure.statements.size.should eq(2)
#   end

#   it "respects operator precedence" do
#     ast = parse("let x = 1 + 2 * 3;")
#     stmt = ast.procedure.statements.first.as(AST::Binding)
#     stmt.value.should be_a(AST::BinaryExpression)
#   end

#   it "parses if expressions" do
#     ast = parse <<-DOIS
#       let x = if 1 == 1 then 2 else 3 end;
#     DOIS
#     stmt = ast.procedure.statements.first.as(AST::Binding)
#     stmt.value.should be_a(AST::IfExpression)
#   end

#   it "parses field access" do
#     ast = parse("let x = p.x;")
#     stmt = ast.procedure.statements.first.as(AST::Binding)
#     stmt.value.should_not be_nil
#   end

#   it "parses chained field access" do
#     ast = parse("let x = p.a.b;")
#     stmt = ast.procedure.statements.first.as(AST::Binding)
#     stmt.value.should_not be_nil
#   end

#   it "parses function calls" do
#     ast = parse("let x = add$(1, 2);")
#     stmt = ast.procedure.statements.first.as(AST::Binding)
#     stmt.value.should_not be_nil
#   end

#   it "parses nested function calls" do
#     ast = parse("let x = add$(mul$(2, 3), 4);")
#     stmt = ast.procedure.statements.first.as(AST::Binding)
#     stmt.value.should_not be_nil
#   end

#   it "parses generic type identifiers" do
#     ast = parse <<-DOIS
#       let x : Maybe(Int) = nil;
#     DOIS
#     stmt = ast.procedure.statements.first.as(AST::Binding)
#     stmt.type_id.should_not be_nil
#   end

#   it "parses match with multiple arms" do
#     ast = parse <<-DOIS
#       match x then
#         Some(value = v) => v,
#         Nil => 0
#       end;
#     DOIS
#     stmt = ast.procedure.statements.first
#     stmt.should_not be_nil
#   end

#   it "fails on incomplete function declaration" do
#     expect_parse_error <<-DOIS
#       fn add $ (a : Int) : Int =>
#     DOIS
#   end

#   it "handles empty function call arguments" do
#     ast = parse("let x = f$();")
#     stmt = ast.procedure.statements.first.as(AST::Binding)
#     stmt.value.should_not be_nil
#   end

#   it "handles deeply nested parentheses" do
#     ast = parse("let x = (((1)));")
#     stmt = ast.procedure.statements.first.as(AST::Binding)
#     stmt.value.should_not be_nil
#   end

#   it "handles extra whitespace" do
#     ast = parse("let    x   =    5   ;")
#     stmt = ast.procedure.statements.first
#     stmt.should be_a(AST::Binding)
#   end

#   it "fails on unmatched parentheses" do
#     expect_parse_error("let x = (1 + 2;")
#   end

#   it "fails on missing end in if" do
#     expect_parse_error <<-DOIS
#       let x = if true then 1 else 2;
#     DOIS
#   end

#   it "parses unary expressions" do
#     ast = parse("let x = -5;")
#     stmt = ast.procedure.statements.first.as(AST::Binding)
#     stmt.value.should_not be_nil
#   end

#   it "parses chained calls and access" do
#     ast = parse("let x = f$(1).a.b;")
#     stmt = ast.procedure.statements.first.as(AST::Binding)
#     stmt.value.should_not be_nil
#   end

#   it "parses multiple match arms with commas" do
#     ast = parse <<-DOIS
#       match x then
#         Nil => 0,
#         Some(value = v) => v
#       end;
#     DOIS
#     stmt = ast.procedure.statements.first
#     stmt.should_not be_nil
#   end

#   it "fails on stray comma in arguments" do
#     expect_parse_error("let x = f$(,);")
#   end
# end
