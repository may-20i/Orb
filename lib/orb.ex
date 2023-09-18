defmodule Orb do
  @moduledoc """
  Write WebAssembly modules with Elixir.

  WebAssembly is a low-level language. You work with integers and floats, can perform operations on them like adding or multiplication, and then read and write those values to a block of memory. There’s no concept of a “string” or an “array”, let alone a “hash map” or “HTTP request”.

  That’s where a library like Orb can help out. It takes full advantage of Elixir’s language features by becoming a compiler for WebAssembly. You can define WebAssembly modules in Elixir for “string” or “hash map”, and compose them together into a final module.

  That WebAssembly module can then run in every major application environment: browsers, servers, the edge, and mobile devices like phones, tablets & laptops. This story is still being developed, but I believe like other web standards like JSON, HTML, and HTTP, that WebAssembly will become a first-class citizen on any platform. It’s Turing-complete, designed to be backwards compatible, fast, and works almost everywhere.

  ## Example

  Let’s create a module that calculates the average of a set of numbers.

  WebAssembly modules can have state. Here will have two pieces of state: a total `count` and a running `tally`. These are stored as **globals**. (If you are familiar with object-oriented programming, you can think of them as instance variables).

  Our module will export two functions: `insert` and `calculate_mean`. These two functions will work with the `count` and `tally` globals.

  ```elixir
  defmodule CalculateMean do
    use Orb

    I32.global(count: 0, tally: 0)

    defw insert(element: I32) do
      @count = @count + 1
      @tally = @tally + element
    end

    defw calculate_mean(), I32 do
      @tally / @count
    end
  end
  ```

  One thing you’ll notice is that we must specify the type of function parameters and return values. Our `insert` function accepts a 32-bit integer, denoted using `I32`. It returns no value, while `calculate_mean` is annotated to return a 32-bit integer.

  We get to write math with the intuitive `+` and `/` operators. Let’s see the same module without the magic: no math operators and without `@` conveniences for working with globals:

  ```elixir
  defmodule CalculateMean do
    use Orb

    I32.global(count: 0, tally: 0)

    defw insert(element: I32) do
      I32.add(global_get(:count), 1)
      global_set(:count)
      I32.add(global_get(:tally), element)
      global_set(:tally)
    end

    defw calculate_mean(), I32 do
      I32.div_u(global_get(:tally), global_get(:count))
    end
  end
  ```

  This is the exact same logic as before. In fact, this is what the first version expands to. Orb adds “sugar syntax” to make authoring WebAssembly nicer, to make it feel like writing Elixir or Ruby.

  ## Functions

  In Elixir you define functions publicly available outside the module with `def/1`, and functions private to the module with `defp/1`. Orb follows the same suffix convention with `func/2` and `funcp/2`.

  Consumers of your WebAssembly module will only be able to call exported functions defined using `func/2`. Making a function public in WebAssembly is known as “exporting”.

  ## Stack based

  While it looks like Elixir, there are some key differences between it and programs written in Orb. The first is that state is mutable. While immutability is one of the best features of Elixir, in WebAssembly variables are mutable because raw computer memory is mutable.

  The second key difference is that WebAssembly is stack based. Every function has an implicit stack of values that you can push and pop from. This paradigm allows WebAssembly runtimes to efficiently optimize for raw CPU registers whilst not being platform specific.

  In Elixir when you write:

  ```elixir
  def example() do
    1
    2
    3
  end
  ```

  The first two lines with `1` and `2` are inert — they have no effect — and the result from the function is the last line `3`.

  In WebAssembly / Orb when you write the same sort of thing:

  ```elixir
  defw example() do
    1
    2
    3
  end
  ```

  Then what’s happening is that we are pushing `1` onto the stack, then `2`, and then `3`. Now the stack has three items on it. Which will become our return value: a tuple of 3 integers. (Our function has no return type specified, so this will be an error if you attempted to compile the resulting module).

  So the correct return type from this function would be a tuple of three integers:

  ```elixir
  defw example(), {I32, I32, I32} do
    1
    2
    3
  end
  ```

  If you prefer, Orb allows you to be explicit with your stack pushes with `Orb.DSL.push/1`:

  ```elixir
  defw example(), {I32, I32, I32} do
    push(1)
    push(2)
    push(3)
  end
  ```

  You can use the stack to unlock novel patterns, but for the most part Orb avoids the need to interact with it. It’s just something to keep in mind if you are used to lines of code with simple values not having any side effects.

  ## Locals

  Locals are variables that live for the lifetime of a function. They must be specified upfront with their type alongside the function’s definition, and are initialized to zero.

  Here we have two locals: `under?` and `over?`, both 32-bit integers. We can set their value and then read them again at the bottom of the function.

  ```elixir
  defmodule WithinRange do
    use Orb

    defw validate(num: I32), I32, under?: I32, over?: I32 do
      under? = num < 1
      over? = num > 255

      not (under? or over?)
    end
  end
  ```

  ## Globals

  Globals are like locals, but live for the duration of the entire running module’s life. Their initial type and value are specified upfront.

  Globals by default are internal: nothing outside the module can see them. They can be exported to expose them to the outside world.

  When exporting a global you decide if it is `:readonly` or `:mutable`. Internal globals are mutable by default.

  ```elixir
  I32.global(some_internal_global: 99)

  I32.global(:readonly, some_internal_global: 99)

  I32.export_global(:readonly, some_public_constant: 1001)

  I32.export_global(:mutable, some_public_variable: 42)

  # You can define multiple globals at once:
  I32.global(magic_number_a: 99, magic_number_b: 12, magic_number_c: -5)
  ```

  You can read or write to a global using the `@` prefix:

  ```elixir
  defmodule Counter do
    use Orb

    I32.global(counter: 0)

    defw increment() do
      @counter = @counter + 1
    end
  end
  ```

  ## Memory

  WebAssembly provides a buffer of memory when you need more than a handful global integers or floats. This is a contiguous array of random-access memory which you can freely read and write to.

  ### Pages

  WebAssembly Memory comes in 64 KiB segments called pages. You use some multiple of these 64 KiB (64 * 1024 = 65,536 bytes) pages.

  By default your module will have **no** memory, so you must specify how much memory you want upfront.

  Here’s an example with 16 pages (1 MiB) of memory:

  ```elixir
  defmodule Example do
    use Orb

    Memory.pages(16)
  end
  ```

  ### Reading & writing memory

  To read from memory, you can use the `Memory.load/2` function. This loads a value at the given memory address. Addresses are themselves 32-bit integers. This mean you can perform pointer arithmetic to calculate whatever address you need to access.

  However, this can prove unsafe as it’s easy to calculate the wrong address and corrupt your memory. For this reason, Orb provides higher level constructs for making working with memory pointers more pleasant, which are detailed later on.

  ```elixir
  defmodule Example do
    use Orb

    Memory.pages(1)

    defw get_int32(), I32 do
      Memory.load!(I32, 0x100)
    end

    defw set_int32(value: I32) do
      Memory.store!(I32, 0x100, value)
    end
  end
  ```

  ### Initializing memory with data

  You can populate the initial memory of your module using `Orb.Memory.initial_data/1`. This accepts an memory offset and the string to write there.

  ```elixir
  defmodule MimeTypeDataExample do
    use Orb

    Memory.pages(1)

    wasm do
      Memory.initial_data(offset: 0x100, string: "text/html")
      Memory.initial_data(offset: 0x200, string: \"""
        <!doctype html>
        <meta charset=utf-8>
        <h1>Hello world</h1>
        \""")
    end

    defw get_mime_type(), I32 do
      0x100
    end

    defw get_body(), I32 do
      0x200
    end
  end
  ```

  Having to manually allocate and remember each memory offset is a pain, so Orb provides conveniences which are detailed in the next section.

  ## Strings constants

  You can use constant strings with the `~S` sigil. These will be extracted as initial data definitions at the start of the WebAssembly module, and their memory offsets substituted in their place.

  Each string is packed together for maximum efficiency of memory space. Strings are deduplicated, so you can use the same string constant multiple times and a single allocation will be made.

  String constants in Orb are nul-terminated.

  ```elixir
  defmodule MimeTypeStringExample do
    use Orb

    Memory.pages(1)

    defw get_mime_type(), I32 do
      ~S"text/html"
    end

    defw get_body(), I32 do
      ~S\"""
      <!doctype html>
      <meta charset=utf-8>
      <h1>Hello world</h1>
      \"""
    end
  end
  ```

  ## Control flow

  Orb supports control flow with `if`, `block`, and `loop` statements.

  ### If statements

  If you want to run logic conditionally, use an `if` statement.

  ```elixir
  if @party_mode? do
    music_volume = 100
  end
  ```

  You can add an `else` clause:

  ```elixir
  if @party_mode? do
    music_volume = 100
  else
    music_volume = 30
  end
  ```

  If you want a ternary operator (e.g. to map from one value to another), you can use `Orb.I32.when?/2` instead:

  ```elixir
  music_volume = I32.when? @party_mode? do
    100
  else
    30
  end
  ```

  These can be written on single line too:

  ```elixir
  music_volume = I32.when?(@party_mode?, do: 100, else: 30)
  ```

  ### Loops

  Loops look like the familiar construct in other languages like JavaScript, with two key differences: each loop has a name, and loops by default stop unless you explicitly tell them to continue.

  ```elixir
  i = 0
  loop CountUp do
    i = i + 1

    CountUp.continue(if: i < 10)
  end
  ```

  Each loop is named, so if you nest them you can specify which particular one to continue.

  ```elixir
  total_weeks = 10
  weekday_count = 7
  week = 0
  weekday = 0
  loop Weeks do
    loop Weekdays do
      # Do something here with week and weekday

      weekday = weekday + 1
      Weekdays.continue(if: weekday < weekday_count)
    end

    week = week + 1
    Weeks.continue(if: week < total_weeks)
  end
  ```

  #### Iterators

  Iterators are an upcoming feature, currently part of SilverOrb that will hopefully become part of Orb itself.

  ### Blocks

  Blocks provide a structured way to skip code.

  ```elixir
  Control.block Validate do
    Validate.break(if: i < 0)

    # Do something with i
  end
  ```

  Blocks can have a type.

  ```elixir
  Control.block Double, I32 do
    if i < 0 do
      push(0)
      Double.break()
    end

    push(i * 2)
  end
  ```

  ## Calling other functions

  When you use `defw`, a corresponding Elixir function is defined for you using `def`.

  ```elixir
  defw magic_number(), I32 do
    42
  end
  ```

  ```elixir
  defw some_example(), n: I32 do
    n = magic_number()
  end
  ```

  You can also use `Orb.DSL.typed_call/3` to manually call functions defined within your module. Currently, the parameters are not checked, so you must ensure you are calling with the correct arity and types.

  ```elixir
  char = typed_call(I32, :encode_html_char, char)
  ```

  ## Composing modules together

  Any functions from one module can be included into another to allow code reuse.

  When you `use Orb`, `funcp` and `func` functions are defined on your Elixir module for you. Calling these from another module will copy any functions across.

  ```elixir
  defmodule A do
    use Orb

    defwi square(n: I32), I32 do
      n * n
    end
  end
  ```

  The `defwi` means that that WebAssembly function remains _internal_ but a public Elixir function is defined.

  ```elixir
  defmodule B do
    use Orb

    # Copies all functions defined in A as private functions into this module.
    wasm do
      A.funcp()
    end

    # Allows square to be called by Elixir.
    import A

    defw example(n: I32), I32 do
      square(42)
    end
  end
  ```

  You can pass a name to `YourSourceModule.funcp(name)` to only copy that particular function across.

  ```elixir
  defmodule A do
    use Orb

    defwi square(n: I32), I32 do
      n * n
    end

    defwi double(n: I32), I32 do
      2 * n
    end
  end
  ```

  ```elixir
  defmodule B do
    use Orb

    wasm do
      A.funcp(:square)
    end

    import A, only: [square: 1]

    defw example(n: I32), I32 do
      square(42)
    end
  end
  ```

  ## Importing

  Your running WebAssembly module can interact with the outside world by importing globals and functions.

  ## Use Elixir features

  - Piping

  ## Inline

  - `inline do:`
    - Module attributes
    - `wasm do:`
  - `inline for`

  ### Custom types with `Access`

  TODO: extract this into its own section.

  ## Define your own functions and macros

  ## Hex packages

  - SilverOrb
      - String builder
  - GoldenOrb

  ## Running your module
  """

  alias Orb.Ops
  alias Orb.Memory
  require Ops

  defmacro __using__(_opts) do
    quote do
      import Orb
      import Orb.DefwDSL
      alias Orb.{I32, I64, S32, U32, F32, Memory, Table}
      require Orb.{I32, F32, Table, Memory}

      @before_compile unquote(__MODULE__).BeforeCompile

      def __wasm_body__(_), do: []
      defoverridable __wasm_body__: 1

      # TODO: rename these to orb_ prefix instead of wasm_ ?
      Module.put_attribute(__MODULE__, :wasm_name, __MODULE__ |> Module.split() |> List.last())

      Module.register_attribute(__MODULE__, :wasm_memory, accumulate: true)

      Module.register_attribute(__MODULE__, :wasm_globals, accumulate: true)

      Module.register_attribute(__MODULE__, :wasm_types, accumulate: true)
      Module.register_attribute(__MODULE__, :wasm_table_allocations, accumulate: true)
      Module.register_attribute(__MODULE__, :wasm_imports, accumulate: true)
      Module.register_attribute(__MODULE__, :wasm_body, accumulate: true)
      Module.register_attribute(__MODULE__, :wasm_constants, accumulate: true)
    end
  end

  # TODO: extract?
  defmodule VariableReference do
    @moduledoc false

    defstruct [:global_or_local, :identifier, :type]

    alias Orb.Instruction

    def global(identifier, type) do
      %__MODULE__{global_or_local: :global, identifier: identifier, type: type}
    end

    def local(identifier, type) do
      %__MODULE__{global_or_local: :local, identifier: identifier, type: type}
    end

    def as_set(%__MODULE__{global_or_local: :local, identifier: identifier}) do
      {:local_set, identifier}
    end

    @behaviour Access

    @impl Access
    def fetch(%__MODULE__{global_or_local: :local, identifier: _identifier, type: :i32} = ref,
          at: offset
        ) do
      ast = Instruction.i32(:load, Instruction.i32(:add, ref, offset))
      {:ok, ast}
    end

    def fetch(
          %__MODULE__{global_or_local: :local, identifier: _identifier, type: mod} = ref,
          key
        ) do
      mod.fetch(ref, key)
    end

    @impl Access
    def get_and_update(_data, _key, _function) do
      raise UndefinedFunctionError, module: __MODULE__, function: :get_and_update, arity: 3
    end

    @impl Access
    def pop(_data, _key) do
      raise UndefinedFunctionError, module: __MODULE__, function: :pop, arity: 2
    end

    defimpl Orb.ToWat do
      def to_wat(%VariableReference{global_or_local: :global, identifier: identifier}, indent) do
        [indent, "(global.get $", to_string(identifier), ?)]
      end

      def to_wat(%VariableReference{global_or_local: :local, identifier: identifier}, indent) do
        [indent, "(local.get $", to_string(identifier), ?)]
      end
    end
  end

  defp do_module_body(block, env) do
    block = interpolate_external_values(block, env)

    block_items =
      case block do
        {:__block__, _meta, block_items} -> block_items
        single -> List.wrap(single)
      end

    # block_items = Macro.expand(block_items, env)
    # block_items = block_items

    {block_items, constants} =
      Macro.prewalk(block_items, [], fn
        {:const, _, [str]}, constants when is_binary(str) ->
          {quote(do: Orb.__data_for_constant(unquote(str))), [str | constants]}

        {:const, _, [expression]}, constants ->
          {quote(do: Orb.__data_for_constant(unquote(expression))), [expression | constants]}

        {:sigil_S, _, [{:<<>>, _, [str]}, _]}, constants ->
          {
            quote(do: Orb.__data_for_constant(unquote(str))),
            [str | constants]
          }

        # FIXME: have to decide whether supporting ~s and interpolation is too hard.
        {:sigil_s, _, [{:<<>>, _, [str]}, _]}, constants ->
          {
            quote(do: Orb.__data_for_constant(unquote(str))),
            [str | constants]
          }

        other, constants ->
          {other, constants}
      end)

    constants = Enum.reverse(constants)

    %{
      body: block_items,
      constants: constants
    }
  end

  defmodule BeforeCompile do
    @moduledoc false

    defmacro __before_compile__(_env) do
      quote do
        def __wasm_constants__(), do: Orb.Constants.from_attribute(@wasm_constants)

        @wasm_global_types Map.new(List.flatten(@wasm_globals), fn global ->
                             {global.name, global.type}
                           end)
                           |> Map.merge(%{__MODULE__: __MODULE__})
        def __wasm_global_type__(global_name) when is_atom(global_name),
          do: Map.fetch!(@wasm_global_types, global_name)

        def __wasm_table_allocations__(),
          do: Orb.Table.Allocations.from_attribute(@wasm_table_allocations)

        def __wasm_module__() do
          get_global_type = &__wasm_global_type__/1

          # I tried having this be a Macro.var but it’s not working.
          # So resort to the ultimate hole puncher.
          Process.put({Orb, :global_types}, get_global_type)
          body = __wasm_body__(get_global_type)
          Process.delete({Orb, :global_types})

          Orb.ModuleDefinition.new(
            name: @wasm_name,
            types: @wasm_types |> Enum.reverse() |> List.flatten(),
            table_size: @wasm_table_allocations |> List.flatten() |> length(),
            imports: @wasm_imports |> Enum.reverse() |> List.flatten(),
            globals: @wasm_globals |> Enum.reverse() |> List.flatten(),
            memory: Memory.from(@wasm_memory),
            constants: Orb.Constants.from_attribute(@wasm_constants),
            # body: @wasm_body |> Enum.reverse() |> List.flatten()
            body: body
          )
        end

        # Orb.DefwDSL.define_helpers(__wasm_body__())

        # def func(),
        #   do: Orb.ModuleDefinition.func_ref_all!(__MODULE__)

        def _func(name),
          do: Orb.ModuleDefinition.func_ref!(__MODULE__, name)

        @doc "Include all internal (`defwi` & `defwp`) WebAssembly functions from this module’s Orb definition into the context’s module."
        # def include() do
        #   Orb.wasm do
        #     # Orb.ModuleDefinition.Include.all_internal(__MODULE__)
        #     Orb.ModuleDefinition.funcp_ref_all!(__MODULE__)
        #   end
        # end

        @doc "Import all WebAssembly functions from this module’s Orb definition."
        def funcp(),
          do: Orb.ModuleDefinition.funcp_ref_all!(__MODULE__)

        @doc "Import a specific WebAssembly function from this module’s Orb definition."
        def funcp(name),
          do: Orb.ModuleDefinition.funcp_ref!(__MODULE__, name)

        @doc "Convert this module’s Orb definition to WebAssembly text (Wat) format."
        def to_wat(), do: Orb.to_wat(__wasm_module__())
      end
    end
  end

  defmacro __data_for_constant(value) do
    quote do
      __wasm_constants__()
      |> Orb.Constants.lookup(unquote(value))
    end
  end

  def __mode_pre(mode) do
    dsl =
      case mode do
        Orb.S32 ->
          quote do
            import Orb.I32.DSL
            import Orb.S32.DSL
            import Orb.Global.DSL
          end

        Orb.U32 ->
          quote do
            import Orb.I32.DSL
            import Orb.U32.DSL
            import Orb.Global.DSL
          end

        Orb.F32 ->
          quote do
            import Orb.F32.DSL
            import Orb.Global.DSL
          end

        :no_magic ->
          []
      end

    quote do
      import Kernel,
        except: [
          if: 2,
          @: 1,
          +: 2,
          -: 2,
          *: 2,
          /: 2,
          <: 2,
          >: 2,
          <=: 2,
          >=: 2,
          ===: 2,
          !==: 2,
          not: 1,
          or: 2
        ]

      # TODO: should this be omitted if :no_magic is passed?
      import Orb.IfElse.DSL
      unquote(dsl)
    end
  end

  defp mode_post(mode) do
    dsl =
      case mode do
        Orb.S32 ->
          quote do
            import Orb.I32.DSL, only: []
            import Orb.S32.DSL, only: []
            import Orb.Global.DSL, only: []
          end

        Orb.U32 ->
          quote do
            import Orb.I32.DSL, only: []
            import Orb.U32.DSL, only: []
            import Orb.Global.DSL, only: []
          end

        Orb.F32 ->
          quote do
            import Orb.F32.DSL, only: []
            import Orb.Global.DSL, only: []
          end

        :any ->
          quote do
            import Orb.I32.DSL, only: []
            import Orb.U32.DSL, only: []
            import Orb.S32.DSL, only: []
            import Orb.F32.DSL, only: []
            import Orb.Global.DSL, only: []
          end

        :no_magic ->
          []
      end

    quote do
      import Kernel
      import Orb.IfElse.DSL, only: []
      unquote(dsl)
    end
  end

  @doc """
  Enter WebAssembly.
  """
  defmacro wasm(mode \\ nil, do: block) do
    # block = interpolate_external_values(block, __ENV__)

    mode = mode || Module.get_attribute(__CALLER__.module, :wasm_mode, Orb.S32)
    mode = Macro.expand_literals(mode, __CALLER__)
    pre = __mode_pre(mode)
    post = mode_post(mode)

    %{body: body, constants: constants} = do_module_body(block, __CALLER__)

    Module.register_attribute(__CALLER__.module, :wasm_constants, accumulate: true)
    # Module.put_attribute(__CALLER__.module, :wasm_constants, constants)

    quote do
      with do
        @wasm_constants unquote(constants)

        unquote(pre)
        import Orb, only: []
        import Orb.DSL
        require Orb.Control, as: Control

        # with do
        #   # Process.put()
        #   # import Orb.DefwDSL
        #   # unquote(body)

        #   Orb.DefwDSL.define_helpers(unquote(body)) |> IO.inspect()
        # end

        # @wasm_body unquote(body)

        def __wasm_body__(wasm_global_type) do
          super(wasm_global_type) ++ unquote(body)
        end

        defoverridable __wasm_body__: 1
      end

      unquote(post)
    end
  end

  @doc """
  Declare a snippet of Orb AST for reuse. Enables DSL, with additions from `mode`.
  """
  defmacro snippet(mode \\ Orb.S32, locals \\ [], do: block) do
    block = interpolate_external_values(block, __CALLER__)

    mode = Macro.expand_literals(mode, __CALLER__)
    pre = __mode_pre(mode)
    post = mode_post(mode)

    block_items =
      case block do
        {:__block__, _meta, items} -> items
        single -> [single]
      end

    locals =
      for {key, type} <- locals, into: %{} do
        {key, Macro.expand_literals(type, __CALLER__)}
      end

    quote do
      # We want to import and un-import. so we use `with` as a finite scope.
      with do
        unquote(pre)

        import Orb.DSL
        dsl_items = unquote(Orb.DSL.do_snippet(locals, block_items))
        import Orb.DSL, only: []

        unquote(post)

        dsl_items
      end
    end
  end

  defp interpolate_external_values(ast, _env) do
    Macro.postwalk(ast, fn
      {:^, _, [term]} ->
        quote do
          with do
            unquote(mode_post(:any))
            import Kernel

            unquote(term)
          end
        end

      {:^, _, _other} ->
        raise "Invalid ^. Expected single argument."

      other ->
        other
    end)
  end

  defmacro types(modules) do
    quote do
      @wasm_types (for mod <- unquote(modules) do
                     %Orb.Type{
                       name: mod.type_name(),
                       inner_type: mod.wasm_type()
                     }
                   end)
    end
  end

  defmacro functype(call, result) do
    env = __ENV__

    call = Macro.expand_once(call, env)

    {name, args} =
      case Macro.decompose_call(call) do
        :error -> {Orb.DSL.__expand_identifier(call, env), []}
        {name, []} -> {name, []}
        {name, [keywords]} when is_list(keywords) -> {name, keywords}
      end

    param_type =
      case for {_, type} <- args, do: Macro.expand_literals(type, env) do
        [] -> nil
        list -> List.to_tuple(list)
      end

    quote do
      @wasm_types %Orb.Type{
        name: unquote(name),
        inner_type: %Orb.Func.Type{
          params: unquote(Macro.escape(param_type)),
          result: unquote(result)
        }
      }
    end
  end

  defmacro include(mod) do
    quote do
      wasm do
        Orb.ModuleDefinition.funcp_ref_all!(unquote(mod))
      end
    end
  end

  @doc """
  Declare a WebAssembly import for a function or global.
  """
  defmacro wasm_import(mod, entries) when is_atom(mod) and is_list(entries) do
    quote do
      @wasm_imports (for {name, type} <- unquote(entries) do
                       %Orb.Import{module: unquote(mod), name: name, type: type}
                     end)
    end
  end

  @doc """
  Convert Orb AST into WebAssembly text format.
  """
  def to_wat(term) when is_atom(term) do
    Process.put(Orb.DSL, true)

    term.__wasm_module__() |> Orb.ToWat.to_wat("") |> IO.chardata_to_string()
  end

  def to_wat(term) do
    Process.put(Orb.DSL, true)

    term |> Orb.ToWat.to_wat("") |> IO.chardata_to_string()
  end

  def __get_block_items(block) do
    case block do
      nil -> nil
      {:__block__, _meta, block_items} -> block_items
      single -> [single]
    end
  end

  def __lookup_global_type!(global_identifier) do
    Process.get({Orb, :global_types}).(global_identifier)
  end
end
