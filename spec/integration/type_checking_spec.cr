require "../spec_helper"

describe DoisC::TypeChecking do
  # wraps input string in module and main proc for executable compilation
  def wrap_dois_main(source : String)
    <<-DOIS
      module Main
        proc main() do
          #{source}
        end
      end
    DOIS
  end

  it "accepts a simple valid program" do
    check <<-DOIS
      let x = 5;
    DOIS
  end

  it "accepts simple function usage" do
    check <<-DOIS
      fn add $ (a : Int, b : Int) : Int =>
        a + b
      end

      let x = add$(1, 2);
    DOIS
  end

  it "rejects invalid assignment" do
    expect_type_error <<-DOIS
      let x : Int = "hello";
    DOIS
  end

  it "rejects invalid function call arguments" do
    expect_type_error <<-DOIS
      fn add $ (a : Int, b : Int) : Int =>
        a + b
      end

      let x = add$(1, "oops");
    DOIS
  end

  it "handles generics with Maybe" do
    check <<-DOIS
      type Some<T> has value : T end
      type Maybe<T> is Some(T) | Nil end

      let a = Some(value = 3);
      let b : Maybe(Int) = a;
    DOIS
  end

  it "handles control flow returning unions" do
    check <<-DOIS
      type Some<T> has value : T end
      type Maybe<T> is Some(T) | Nil end

      fn test $ (x : Int) : Maybe(Int) =>
        if x == 0 then
          nil
        else
          Some(x)
        end
      end
    DOIS
  end

  it "handles generic function identity" do
    check <<-DOIS
      fn id<T> $ (x : T) : T =>
        x
      end

      let a = id$(5);
    DOIS
  end

  it "rejects mismatched generic usage" do
    expect_type_error <<-DOIS
      fn id<T> $ (x : T) : T =>
        x
      end

      let a : String = id$(5);
    DOIS
  end

  it "handles generic structs" do
    check <<-DOIS
      type Point<T> has x : T, y : T end

      let p = Point(x = 1, y = 2);
      let q : Point(Int) = p;
    DOIS
  end

  it "rejects incorrect generic struct assignment" do
    expect_type_error <<-DOIS
      type Point<T> has x : T, y : T end

      let p = Point(x = 1, y = 2);
      let q : Point(String) = p;
    DOIS
  end

  it "handles nested generics" do
    check <<-DOIS
      type Some<T> has value : T end

      let x = Some(value = Some(value = 5));
    DOIS
  end

  it "handles match expressions correctly" do
    check <<-DOIS
      type Some<T> has value : T end
      type Maybe<T> is Some(T) | Nil end

      fn unwrap $ (m : Maybe(Int)) : Int =>
        match m then
          Some(value = v) => v,
          Nil => 0
        end
      end
    DOIS
  end

  it "rejects invalid match patterns" do
    expect_type_error <<-DOIS
      type Some<T> has value : T end
      type Maybe<T> is Some(T) | Nil end

      fn bad $ (m : Maybe(Int)) : Int =>
        match m then
          Some(value = v) => "oops",
          Nil => 0
        end
      end
    DOIS
  end

  it "rejects missing match cases if required" do
    expect_type_error <<-DOIS
      type Some<T> has value : T end
      type Maybe<T> is Some(T) | Nil end

      fn bad $ (m : Maybe(Int)) : Int =>
        match m then
          Some(value = v) => v
        end
      end
    DOIS
  end

  it "handles function returning generic types" do
    check <<-DOIS
      type Some<T> has value : T end

      fn wrap<T> $ (x : T) : Some(T) =>
        Some(x)
      end

      let x = wrap$(5);
    DOIS
  end

  it "rejects invalid return types" do
    expect_type_error <<-DOIS
      fn bad $ () : Int =>
        "not an int"
      end
    DOIS
  end

  it "handles chained function calls with types" do
    check <<-DOIS
      fn add $ (a : Int, b : Int) : Int =>
        a + b
      end

      fn double $ (x : Int) : Int =>
        add$(x, x)
      end

      let y = double$(5);
    DOIS
  end

  it "enforces consistent generic usage across parameters" do
    expect_type_error <<-DOIS
      fn pair<T> $ (a : T, b : T) : T =>
        a
      end

      let x = pair$(1, "oops");
    DOIS
  end

  it "propagates generics through multiple functions" do
    check <<-DOIS
      fn id<T> $ (x : T) : T =>
        x
      end

      fn wrap<T> $ (x : T) : T =>
        id$(x)
      end

      let y = wrap$(5);
    DOIS
  end

  it "rejects using union without matching" do
    expect_type_error <<-DOIS
      type Some<T> has value : T end
      type Maybe<T> is Some(T) | Nil end

      fn bad $ (m : Maybe(Int)) : Int =>
        m
      end
    DOIS
  end

  it "binds pattern variables with correct types" do
    check <<-DOIS
      type Some<T> has value : T end
      type Maybe<T> is Some(T) | Nil end

      fn test $ (m : Maybe(Int)) : Int =>
        match m then
          Some(value = v) => v + 1,
          Nil => 0
        end
      end
    DOIS
  end

  it "rejects incorrect constructor field types" do
    expect_type_error <<-DOIS
      type Point<T> has x : T, y : T end

      let p = Point(x = 1, y = "oops");
    DOIS
  end

  it "handles multiple generic instantiations independently" do
    check <<-DOIS
      fn id<T> $ (x : T) : T =>
        x
      end

      let a = id$(5);
      let b = id$("hello");
    DOIS
  end

  it "rejects wrong number of arguments in function call" do
    expect_type_error <<-DOIS
      fn add $ (a : Int, b : Int) : Int =>
        a + b
      end

      let x = add$(1);
    DOIS
  end

  it "rejects wrong number of type arguments in generic type" do
    expect_type_error <<-DOIS
      type Point<T> has x : T, y : T end

      let p : Point = Point(x = 1, y = 2);
    DOIS
  end

  it "handles nested function calls with generics" do
    check <<-DOIS
      fn id<T> $ (x : T) : T =>
        x
      end

      let x = id$(id$(5));
    DOIS
  end

  it "rejects incompatible binary operations" do
    expect_type_error <<-DOIS
      let x = 1 + "hello";
    DOIS
  end

  context "tags ast with type" do
    it "for binding" do
      ast = check <<-DOIS
        let x : Int = 1;
      DOIS
      main_proc = unwrap_main(ast)
      binding = main_proc.statements.first.as(AST::Binding)
      binding.resolved_type.should be_a(T::NominalType)
    end

    it "with simple inference" do
      ast = check <<-DOIS
        let x = 1;
      DOIS
      main_proc = unwrap_main(ast)
      binding = main_proc.statements.first.as(AST::Binding)
      binding.resolved_type.should be_a(T::NominalType)
    end

    it "with literal atomics" do
      ast = check <<-DOIS
        let a = 1;
        let b = 12.3;
        let c = nil;
        let d = 'c';
        let e = "hello";
      DOIS
      main_proc = unwrap_main(ast)
      main_proc.statements.size.should eq(5)
      main_proc.statements.each.with_index do |s, i|
        binding = s.as(AST::Binding)
        type = binding.resolved_type.as(T::NominalType)
        type.definition.should be_a(T::AtomicTypeDefinition)
        expected_types = %w(Int Float Nil Char String)
        type.to_s.should eq(expected_types[i])
      end
    end

    it "with literal collections" do
      ast = check <<-DOIS
        let a = [1, 2, 3];
        let b = ('c', 2.0);
        let c = {0 => "hello", 1 => "world"};
      DOIS
      main_proc = unwrap_main(ast)
      main_proc.statements.size.should eq(3)
      main_proc.statements.each.with_index do |s, i|
        binding = s.as(AST::Binding)
        type = binding.resolved_type.as(T::NominalType)
        type.definition.should be_a(T::AtomicTypeDefinition)
        expected_types = ["Array(Int)", "Tuple(Char, Float)", "Map(Int, String)"]
        type.to_s.should eq(expected_types[i])
      end
    end

    it "for binary expressions" do
      ast = check <<-DOIS
        1 + 2;
      DOIS
      unwrap_expr_stmt(ast).resolved_type.to_s.should eq("Int")
    end

    it "for function calls" do
      ast = check <<-DOIS
        fn add $ (a : Int, b : Int) : Int =>
          a + b
        end

        add$(1, 2);
      DOIS
      unwrap_expr_stmt(ast).resolved_type.to_s.should eq("Int")
    end

    it "for generic calls" do
      ast = check <<-DOIS
        fn id<T> $ (x : T) : T =>
          x
        end

        id$(5);
      DOIS
      unwrap_expr_stmt(ast).resolved_type.to_s.should eq("Int")
    end

    it "for constructor calls" do
      ast = check <<-DOIS
        type Point<T> has x : T, y : T end

        Point(x = 1, y = 2);
      DOIS
      unwrap_expr_stmt(ast).resolved_type.to_s.should eq("Point(Int)")
    end

    it "recursively" do
      ast = check <<-DOIS
        (22.6 - 2) + (2.01 * (3 / 4));
      DOIS
      walk_expressions(unwrap_expr_stmt(ast)) do |expr|
        puts "checking #{expr.to_s}"

        expr.resolved_type.should_not be_nil
      end
    end

    # BUG if expression statement not supported yet
    # it "for if expressions" do
    #   ast = check <<-DOIS
    #     if true then 1 else 0 end;
    #   DOIS
    #   unwrap_expr_stmt(ast).resolved_type.to_s.should eq("Int")
    # end

    it "for match expressions" do
      ast = check <<-DOIS
        match 0 then
          0 => 1,
          1 => 10
        end;
      DOIS
      unwrap_expr_stmt(ast).resolved_type.to_s.should eq("Int")
    end

    it "for unary expressions" do
      ast = check <<-DOIS
        -10;
      DOIS
      unwrap_expr_stmt(ast).resolved_type.to_s.should eq("Int")
    end

    it "for identifier expressions" do
      ast = check <<-DOIS
        let x : Int = 10;
        x;
      DOIS
      unwrap_expr_stmt(ast).resolved_type.to_s.should eq("Int")
    end
  end
end

context "edge case type checking" do
  it "rejects empty literal collections without type context" do
    expect_type_error <<-DOIS
      let x = [];
    DOIS
    expect_type_error <<-DOIS
      let x = {};
    DOIS
  end

  it "accepts empty literal ccollections with type context" do
    check <<-DOIS
      let x : Array(Int) = [];
      let y : Map(String, Char) = {};
    DOIS
  end

  it "rejects empty array without type context" do
    expect_type_error <<-DOIS
      let x = [];
    DOIS
  end

  it "rejects empty map without type context" do
    expect_type_error <<-DOIS
      let x = {};
    DOIS
  end

  it "infers empty array with type annotation" do
    ast = check <<-DOIS
      let x : Array(Int) = [];
    DOIS
    binding = unwrap_main(ast).statements.first.as(AST::Binding)
    binding.resolved_type.to_s.should eq("Array(Int)")
  end

  it "infers empty map with type annotation" do
    ast = check <<-DOIS
      let x : Map(String, Int) = {};
    DOIS
    binding = unwrap_main(ast).statements.first.as(AST::Binding)
    binding.resolved_type.to_s.should eq("Map(String, Int)")
  end

  it "rejects nested generic mismatch in structs" do
    expect_type_error <<-DOIS
      type Box<T> has value : T end
      let x : Box(Box(Int)) = Box(value = Box(value = "oops"));
    DOIS
  end

  it "rejects using generic type without arguments" do
    expect_type_error <<-DOIS
      type Box<T> has value : T end
      let x : Box = Box(value = 5);
    DOIS
  end

  it "rejects pattern matching with wrong types" do
    expect_type_error <<-DOIS
      type Some<T> has value : T end
      match Some(value = 5) then
        Some(value = v) => v + "oops"
      end;
    DOIS
  end

  it "requires exhaustiveness for union types in match" do
    expect_type_error <<-DOIS
      type Some<T> has value : T end
      type Maybe<T> is Some(T) | Nil end
      match Some(value = 5) then
        Some(value = v) => v
      end;
    DOIS
  end

  it "infers types for nested expressions" do
    ast = check <<-DOIS
      type Some<T> has value : T end
      let x = Some(value = Some(value = 5));
    DOIS
    binding = unwrap_main(ast).statements.first.as(AST::Binding)
    type = binding.resolved_type.as(T::NominalType)
    type.definition.name.should eq("Some")
    inner_type = type.type_args.first.as(T::NominalType)
    inner_type.definition.name.should eq("Some")
    inner_inner_type = inner_type.type_args.first.as(T::NominalType)
    inner_inner_type.definition.name.should eq("Int")
  end

  it "rejects ignoring proc result if configured strict" do
    expect_type_error <<-DOIS
      fn do_thing $ () : Int =>
        5
      end
      do_thing$();
    DOIS
  end
end
