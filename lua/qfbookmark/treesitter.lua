local M = {}

---@class QFBookSymbol
---@field kind  string   innermost kind: "fn"|"method"|"class"|"struct"|"impl"|"interface"|"table"|"unknown"
---@field chain string   formatted display string, e.g. " MyClass > ƒ myMethod"

--- Symbol kind → display icon
M.SYMBOL_ICONS = {
  fn = "ƒ",
  method = "ƒ",
  class = "",
  struct = "󰙅",
  impl = "",
  interface = "",
  enum = "",
  table = "",
  unknown = "",
}

--- Map treesitter node_type → our kind string.
local NODE_KIND = {
  -- functions (Lua, JS, TS, Python)
  function_definition = "fn",
  function_declaration = "fn",
  local_function = "fn",
  ["function"] = "fn",
  -- Rust / C / C++ functions
  function_item = "fn",
  -- TS/JS arrow and function expressions
  arrow_function = "fn",
  function_expression = "fn",
  -- methods (Go, JS, TS)
  method_definition = "method",
  method_declaration = "method",
  -- classes
  class_definition = "class",
  class_declaration = "class",

  enum_item = "enum",
  -- structs
  struct_item = "struct", -- Rust
  struct_specifier = "struct", -- C/C++
  struct_type = "struct", -- Go: type_spec > struct_type
  type_spec = "struct", -- Go: type TestStruct struct {}
  -- impl blocks (Rust)
  impl_item = "impl",
  -- interfaces
  interface_declaration = "interface",
  interface_type = "interface", -- Go
  -- tables / objects (Lua)
  table_constructor = "table",
}

--- Extract name text from a name/key node.
--- Handles: identifier, dot/method index expression, string literal.
---@param n?    TSNode
---@param bufnr integer
---@return string | nil
local function node_text(n, bufnr)
  if not n then
    return nil
  end
  local t = n:type()
  -- all identifier variants
  if t == "identifier" or t == "field_identifier" or t == "type_identifier" then
    return vim.treesitter.get_node_text(n, bufnr)
  end
  if t == "dot_index_expression" or t == "method_index_expression" then
    local last = n:named_child(n:named_child_count() - 1)
    return last and vim.treesitter.get_node_text(last, bufnr) or nil
  end
  if t == "string" then
    local raw = vim.treesitter.get_node_text(n, bufnr)
    -- strip surrounding quotes or bracket-quotes
    return raw:match "^['\"](.+)['\"]$" or raw:match "^%[%[(.+)%]%]$" or raw:match "^%[['\"](.+)['\"]%]$" or raw
  end
  return nil
end

--- Collect enclosing scope chain from a starting node walking up the tree.
--- Returns a list of { kind, name } from outermost to innermost.
---
---@param start? TSNode
---@param bufnr integer
---@return { kind: string, name: string }[]
local function collect_scope_chain(start, bufnr)
  local chain = {}

  local function push(kind, name)
    if name and name ~= "" then
      table.insert(chain, 1, { kind = kind, name = name })
    end
  end

  local node = start

  while node do
    local t = node:type()

    -- ── named function / method ────────────────────────────────────────
    if t == "function_definition" or t == "function_declaration" or t == "local_function" then
      local name_node = node:field("name")[1]
      local name = name_node and node_text(name_node, bufnr)
      if name then
        push("fn", name)
      end
      node = node:parent()

    -- ── enum  method ────────────────────────────────────────
    elseif t == "enum_item" then
      local name_node = node:field("name")[1]
      local name = name_node and node_text(name_node, bufnr)
      if name then
        push("enum", name)
      end
      node = node:parent()

    -- Rust: fn foo() / pub fn foo() / pub async fn foo()
    elseif t == "function_item" then
      local name_node = node:field("name")[1]
      local name = name_node and node_text(name_node, bufnr)
      if name then
        push("fn", name)
      end
      node = node:parent()

    -- ── TS/JS arrow function: const foo = () => {}  ───────────────────
    -- tree: lexical_declaration > variable_declarator(name, value=arrow_function)
    elseif t == "arrow_function" then
      local parent = node:parent()
      if not parent then
        break
      end
      -- parent should be variable_declarator
      if parent:type() == "variable_declarator" then
        local name_node = parent:field("name")[1]
        push("fn", node_text(name_node, bufnr))
        node = parent:parent() -- lexical_declaration / variable_declaration
      else
        node = parent
      end

    -- TS/JS: function expression assigned to variable
    -- const foo = function() {}
    elseif t == "function_expression" then
      local parent = node:parent()
      if not parent then
        break
      end
      if parent:type() == "variable_declarator" then
        local name_node = parent:field("name")[1]
        push("fn", node_text(name_node, bufnr))
        node = parent:parent()
      else
        node = parent
      end

    -- TS/JS: method shorthand inside object/class
    -- { foo() {} }  or  class { foo() {} }
    elseif t == "method_definition" or t == "method_declaration" then
      local name_node = node:field("name")[1]
      local name = name_node and node_text(name_node, bufnr)
      if name then
        push("method", name)
      end

      -- Go: extract receiver type from field "receiver"
      -- receiver: parameter_list > parameter_declaration > type_identifier / pointer_type
      local receiver = node:field("receiver")[1]
      if receiver then
        -- walk into receiver to find the type name
        -- parameter_list > parameter_declaration > (pointer_type >) type_identifier
        local function find_receiver_type(n)
          if not n then
            return nil
          end
          local nt = n:type()
          if nt == "type_identifier" then
            return vim.treesitter.get_node_text(n, bufnr)
          end
          -- pointer receiver *TestStruct → pointer_type > type_identifier
          if nt == "pointer_type" then
            return find_receiver_type(n:named_child(0))
          end
          for child in n:iter_children() do
            local result = find_receiver_type(child)
            if result then
              return result
            end
          end
          return nil
        end
        local recv_type = find_receiver_type(receiver)
        if recv_type then
          push("struct", recv_type)
        end
      end

      node = node:parent()

    -- ── anonymous function() — name lives in parent ────────────────────
    elseif t == "function" then
      local parent = node:parent()
      if not parent then
        break
      end
      local pt = parent:type()

      if pt == "pair" then
        -- ["key"] = function()  inside table
        local key = parent:named_child(0)
        push("fn", node_text(key, bufnr))
        node = parent:parent()
      elseif pt == "local_variable_declaration" then
        -- local foo = function()
        local nl = parent:field("namelist")[1] or parent:named_child(0)
        local first = nl and (nl:type() == "identifier" and nl or nl:named_child(0))
        push("fn", node_text(first, bufnr))
        node = parent:parent()
      elseif pt == "assignment_statement" then
        -- foo = function()  or  M.foo = function()
        local vl = parent:field("varlist")[1] or parent:named_child(0)
        local first = vl
          and (
            (
                vl:type() == "identifier"
                or vl:type() == "dot_index_expression"
                or vl:type() == "method_index_expression"
              )
              and vl
            or vl:named_child(0)
          )
        push("fn", node_text(first, bufnr))
        node = parent:parent()
      else
        node = parent
      end

    -- ── class / struct / impl / interface ─────────────────────────────
    elseif t == "class_definition" or t == "class_declaration" then
      local name_node = node:field("name")[1]
      push("class", node_text(name_node, bufnr))
      node = node:parent()
    elseif t == "struct_item" or t == "struct_specifier" then
      local name_node = node:field("name")[1]
      push("struct", node_text(name_node, bufnr))
      node = node:parent()

    -- Go: type TestStruct struct { ... }
    -- tree: type_declaration > type_spec(name=TestStruct) > struct_type
    -- We land on type_spec when walking up from a field inside the struct.
    elseif t == "type_spec" then
      local name_node = node:field("name")[1]
      local type_val = node:field("type")[1]
      local kind = "struct"
      if type_val then
        local tv = type_val:type()
        if tv == "interface_type" then
          kind = "interface"
        elseif tv == "struct_type" then
          kind = "struct"
        end
      end
      push(kind, node_text(name_node, bufnr))
      node = node:parent()

    -- Go: struct_type is the body of the struct — name lives in parent type_spec
    elseif t == "struct_type" then
      local parent = node:parent()
      if parent and parent:type() == "type_spec" then
        local name_node = parent:field("name")[1]
        push("struct", node_text(name_node, bufnr))
        node = parent:parent()
      else
        node = parent
      end

    -- type_declaration wraps type_spec — skip it
    elseif t == "type_declaration" then
      node = node:parent()
    elseif t == "impl_item" then
      -- Rust: impl SystemDb { ... }
      -- field "type" = the type being implemented (type_identifier)
      local type_node = node:field("type")[1]
      local name = node_text(type_node, bufnr)
      -- fallback: scan named children for type_identifier
      if not name then
        for child in node:iter_children() do
          if child:type() == "type_identifier" then
            name = vim.treesitter.get_node_text(child, bufnr)
            break
          end
        end
      end
      if name then
        push("impl", name)
      end
      node = node:parent()

    -- Rust: declaration_list is the body of impl — skip it transparently
    elseif t == "declaration_list" then
      node = node:parent()
    elseif t == "interface_declaration" or t == "interface_type" then
      local name_node = node:field("name")[1]
      push("interface", node_text(name_node, bufnr))
      node = node:parent()

    -- ── table_constructor — find its assigned name ─────────────────────
    elseif t == "table_constructor" then
      local parent = node:parent()
      if not parent then
        break
      end
      local pt = parent:type()

      if pt == "local_variable_declaration" then
        local nl = parent:field("namelist")[1] or parent:named_child(0)
        local first = nl and (nl:type() == "identifier" and nl or nl:named_child(0))
        local name = node_text(first, bufnr)
        push("table", name or "{}")
        node = parent:parent()
      elseif pt == "assignment_statement" then
        local vl = parent:field("varlist")[1] or parent:named_child(0)
        local first = vl and (vl:named_child(0) or vl)
        local name = node_text(first, bufnr)
        push("table", name or "{}")
        node = parent:parent()
      else
        -- anonymous table, still want to show "{}" as context
        push("table", "{}")
        node = parent
      end
    else
      node = node:parent()
    end
  end

  return chain
end

--- Format a scope chain into a display string.
--- Keeps at most 2 innermost levels to avoid overflow.
--- Example: { class "C", fn "A" } → " C > ƒ A"
---@param chain { kind: string, name: string }[]
---@return string   formatted string, or "" if chain is empty
local function format_chain(chain)
  if #chain == 0 then
    return ""
  end

  -- keep only last 2 levels (innermost)
  local start = math.max(1, #chain - 1)
  local parts = {}
  for i = start, #chain do
    local seg = chain[i]
    local icon = M.SYMBOL_ICONS[seg.kind] or M.SYMBOL_ICONS.unknown
    parts[#parts + 1] = icon .. " " .. seg.name
  end
  return table.concat(parts, " > ")
end

--- Resolve enclosing symbol chain at a given buffer position.
--- Uses manual treesitter walker only — nvim-treesitter locals API
--- does not reliably accept a bufnr argument and may return data
--- for the wrong buffer when called outside the target buffer context.
---@param bufnr integer
---@param lnum  integer  1-based
---@param col   integer  0-based
---@return QFBookSymbol
function M.resolve_symbol(bufnr, lnum, col)
  -- ensure the buffer has a filetype so treesitter can attach
  local ft = vim.bo[bufnr].filetype
  if not ft or ft == "" then
    ft = vim.filetype.match { buf = bufnr } or ""
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, ft ~= "" and ft or nil)
  if not ok or not parser then
    return { kind = "unknown", chain = "" }
  end

  -- force a full parse — necessary for hidden buffers that were never rendered
  local trees = parser:parse(true)
  local tree = trees and trees[1]
  if not tree then
    return { kind = "unknown", chain = "" }
  end

  local root = tree:root()
  local row = lnum - 1 -- 0-based

  -- col=0 can land on whitespace/indent for languages like Rust where
  -- the mark was set without a precise column. Use the first non-whitespace
  -- column of the line as a better anchor.
  local effective_col = col
  if col == 0 then
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
    local first_nonws = line:find "%S"
    if first_nonws then
      effective_col = first_nonws - 1 -- 0-based
    end
  end

  local start_node = root:named_descendant_for_range(row, effective_col, row, effective_col)
    or root:descendant_for_range(row, effective_col, row, effective_col)

  -- walk up to first named scope node, then collect chain from there
  local node = start_node
  while node do
    local t = node:type()
    if NODE_KIND[t] then
      local chain = collect_scope_chain(node, bufnr)
      local display = format_chain(chain)
      local innermost = chain[#chain]
      return {
        kind = innermost and innermost.kind or "unknown",
        chain = display,
      }
    end
    node = node:parent()
  end

  return { kind = "unknown", chain = "" }
end

return M
