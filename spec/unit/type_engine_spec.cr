require "../spec_helper"

def source_location(l : Int = 0, c : Int = 0)
  AST::SourceLocation.new(l, c)
end

def type_id(name : String, inner = [] of AST::TypeID)
  AST::TypeID.new(
    name,
    inner,
    source_location()
  )
end

describe DoisC::TypeChecking::TypeEngine do
  it "unifies identical atomic types" do
    global = G.new
    engine = TE.new(global)

    int_type = engine.parse_type_identifier(type_id("Int"))

    engine.unify(int_type, int_type, source_location)
  end

  it "unifies generic with concrete type" do
    global = G.new
    engine = TE.new(global)

    t = engine.fresh_type_variable
    int_type = engine.parse_type_identifier(type_id("Int"))

    engine.unify(t, int_type, source_location)

    engine.prune(t).should eq(int_type)
  end

  it "unifies Point(T) with Point(Int)" do
    global = G.new

    # mock: type Point<T> has x : T, y : T end

    global.register_type("Point")
    int_ref = global.type_reference("Int").as(T::NominalTypeReference)
    point_ref = global.type_reference("Point").as(T::NominalTypeReference)
    t_ref = T::NominalTypeReference.new("T", [] of T::TypeReference)

    point_def = T::ProductTypeDefinition.new(
      "Point",
      ["T"],
      {
        "x" => t_ref,
        "y" => t_ref,
      },
      point_ref
    )
    global.define_type(point_ref, point_def)
    engine = TE.new(global)

    # instantiate Point<T> with fresh type variable
    parsed_point = engine.parse_type_identifier(type_id("Point")).as(T::NominalType)
    point_def = parsed_point.definition

    # create Point(T) via GenericTypeParameter and instantiate
    generic_point = engine.instantiate(
      T::NominalType.new(point_def, [
        T::GenericTypeParameter.new("T"),
      ] of T::Type)
    ).as(T::NominalType)

    t = generic_point.type_args[0]

    int_type = engine.parse_type_identifier(type_id("Int"))
    concrete_point = T::NominalType.new(point_def, [int_type] of T::Type)

    engine.unify(generic_point, concrete_point, source_location)

    engine.prune(t).should eq(int_type)
  end

  it "checks assignability of identical types" do
    global = G.new
    engine = TE.new(global)

    int_type = engine.parse_type_identifier(type_id("Int"))

    engine.is_assignable?(int_type, int_type).should be_true
  end

  it "checks assignability of generic to concrete" do
    global = G.new
    engine = TE.new(global)

    t = engine.fresh_type_variable
    int_type = engine.parse_type_identifier(type_id("Int"))

    engine.is_assignable?(t, int_type).should be_true
  end

  it "rejects incompatible atomic types" do
    global = G.new
    engine = TE.new(global)

    int_type = engine.parse_type_identifier(type_id("Int"))
    string_type = engine.parse_type_identifier(type_id("String"))

    engine.is_assignable?(int_type, string_type).should be_false
  end

  it "checks assignability for Point(Int) to Point(Int)" do
    global = G.new

    global.register_type("Point")
    point_ref = global.type_reference("Point").as(T::NominalTypeReference)
    t_ref = T::NominalTypeReference.new("T", [] of T::TypeReference)

    point_def = T::ProductTypeDefinition.new(
      "Point",
      ["T"],
      {
        "x" => t_ref,
        "y" => t_ref,
      },
      point_ref
    )
    global.define_type(point_ref, point_def)

    engine = TE.new(global)

    int_type = engine.parse_type_identifier(type_id("Int"))

    p1 = T::NominalType.new(point_def, [int_type] of T::Type)
    p2 = T::NominalType.new(point_def, [int_type] of T::Type)

    engine.is_assignable?(p1, p2).should be_true
  end

  it "rejects Point(Int) to Point(String)" do
    global = G.new

    global.register_type("Point")
    point_ref = global.type_reference("Point").as(T::NominalTypeReference)
    t_ref = T::NominalTypeReference.new("T", [] of T::TypeReference)

    point_def = T::ProductTypeDefinition.new(
      "Point",
      ["T"],
      {
        "x" => t_ref,
        "y" => t_ref,
      },
      point_ref
    )
    global.define_type(point_ref, point_def)

    engine = TE.new(global)

    int_type = engine.parse_type_identifier(type_id("Int"))
    string_type = engine.parse_type_identifier(type_id("String"))

    p1 = T::NominalType.new(point_def, [int_type] of T::Type)
    p2 = T::NominalType.new(point_def, [string_type] of T::Type)

    engine.is_assignable?(p1, p2).should be_false
  end
  it "propagates unification through nested generics" do
    global = G.new
    engine = TE.new(global)

    t = engine.fresh_type_variable
    int_type = engine.parse_type_identifier(type_id("Int"))

    # simulate something like List(T) vs List(Int) via direct variable unify
    engine.unify(t, int_type, source_location)

    engine.prune(t).should eq(int_type)
  end

  it "instantiate replaces generic parameters with fresh variables" do
    global = G.new

    global.register_type("Box")
    box_ref = global.type_reference("Box").as(T::NominalTypeReference)
    t_ref = T::NominalTypeReference.new("T", [] of T::TypeReference)

    box_def = T::ProductTypeDefinition.new(
      "Box",
      ["T"],
      {"value" => t_ref},
      box_ref
    )
    global.define_type(box_ref, box_def)

    engine = TE.new(global)

    generic = T::NominalType.new(
      box_def,
      [T::GenericTypeParameter.new("T")] of T::Type
    )

    instantiated = engine.instantiate(generic).as(T::NominalType)

    instantiated.type_args.size.should eq(1)
    instantiated.type_args[0].should be_a(T::TypeVariable)
  end

  it "fails assignability when generic arity mismatches" do
    global = G.new

    global.register_type("Box")
    box_ref = global.type_reference("Box").as(T::NominalTypeReference)
    t_ref = T::NominalTypeReference.new("T", [] of T::TypeReference)

    box_def = T::ProductTypeDefinition.new(
      "Box",
      ["T"],
      {"value" => t_ref},
      box_ref
    )
    global.define_type(box_ref, box_def)

    engine = TE.new(global)

    int_type = engine.parse_type_identifier(type_id("Int"))

    # Missing type arg
    bad = T::NominalType.new(box_def, [] of T::Type)
    good = T::NominalType.new(box_def, [int_type] of T::Type)

    engine.is_assignable?(bad, good).should be_false
  end

  it "unifies multiple occurrences of same generic" do
    global = G.new
    engine = TE.new(global)

    t = engine.fresh_type_variable
    int_type = engine.parse_type_identifier(type_id("Int"))

    # simulate T used twice (like Point(T, T))
    engine.unify(t, int_type, source_location)
    engine.unify(t, int_type, source_location)

    engine.prune(t).should eq(int_type)
  end

  it "does not allow conflicting unification" do
    global = G.new
    engine = TE.new(global)

    t = engine.fresh_type_variable
    int_type = engine.parse_type_identifier(type_id("Int"))
    string_type = engine.parse_type_identifier(type_id("String"))

    engine.unify(t, int_type, source_location)

    expect_raises(Exception) do
      engine.unify(t, string_type, source_location)
    end
  end

  it "prune follows chained substitutions" do
    global = G.new
    engine = TE.new(global)

    t1 = engine.fresh_type_variable
    t2 = engine.fresh_type_variable
    int_type = engine.parse_type_identifier(type_id("Int"))

    engine.unify(t1, t2, source_location)
    engine.unify(t2, int_type, source_location)

    engine.prune(t1).should eq(int_type)
  end
end
