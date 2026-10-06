class CompilationError < Exception
  getter line : Int32
  getter column : Int32

  def initialize(@message : String, @line : Int32, @column : Int32)
    super(message)
  end

  def put_backtrace
    backtrace.each do |ln|
      puts ln
    end
  end
end
