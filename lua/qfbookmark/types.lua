---@alias KeyMode "n" | "x" | "i" | "t" | "o"
---@alias QFBookCurrentState "Local" | "Global"
---@alias QFBookListType "loclist" | "quickfix" | "none"
---@alias QFBookMarkMode "MARK" | "DEBUG" | "NOTE" | "FIX"
---@alias QFBookState "Save Qflist" | "Save Loclist" | "Load"

---@alias QFbookBufferMarkGroup table<string, QFbookBufferMarkEntry>
---@alias QFbookBufferMark table<QFBookMarkMode, QFbookBufferMarkGroup>

---@alias QfBookUiPreview { win?: integer, buf?: integer, wincfg?: table }
---@alias QfBookUiPopup { win?: integer, buf?: integer, preview?: QfBookUiPreview }

---@alias QfBookUiSaveCfg {
--- title: string,
--- target_path: string,
--- is_loc: boolean,
--- cb: function,
--- for_what: "save"|"rename" }

---@alias QfBookEntry {
--- hval: string,
--- id: integer,
--- start_line: integer,
--- line_count: integer,
--- mark: QFbookBufferMarkEntry, }

---@alias QfBookUiPopupCfg {
--- contents: table,
--- content_map: table<integer, QfBookEntry>,
--- win_opts: WinCfg,
--- display_lines: string[],
--- popup?: QfBookUiPopup,
--- is_harpoon?: boolean,
--- is_buffers?: boolean,
--- is_mark_annotation?: boolean,
--- is_note?: boolean,
--- active: string,
--- save?: QfBookUiSaveCfg,
--- selected: table<string, boolean>,
--- data_annotation?: { chunk: QFbookBufferMarkEntry, load_chunk: boolean } }

---@alias QfBookUiWinCfg {
--- save: QFBookUiCfg,
--- save_footer: QFBookUiCfg,
--- mark_preview: QFBookUiCfg,
--- mark: QFBookUiCfg,
--- buffer: QFBookUiCfg,
--- note: QFBookUiCfg,
--- mark_annotation: QFBookUiCfg,
--- mark_annotation_preview: QFBookUiCfg }

---@class QfBookContextQFlist
---@field name string
---@field bufnr? integer

---@class QFBookLists
---@field title string
---@field items table[]
---@field id? integer
---@field context? QfBookContextQFlist | string

---@class QFBookListResults
---@field quickfix QFBookLists
---@field location QFBookLists

---@class QFBookSpec
---@field icon string
---@field hl_group string
---@field alt string

---@class QFBookKeywords
---@field MARK QFBookSpec
---@field FIX QFBookSpec
---@field DEBUG QFBookSpec
---@field NOTE QFBookSpec

---@class QFBookBufferItem
---@field info vim.fn.getbufinfo.ret.item & { col?: integer }
---@field bufnr integer
---@field flag string

---@class QFbookBufferMarkEntry
---@field bufnr integer | nil
---@field filename string
---@field line integer
---@field col integer
---@field text string
---@field harpoon string
---@field mark_mode string
---@field inserted_at integer
---@field fn_name string
---@field note string[]
---@field id integer

---@class QFBookExtermarks
---@field excluded { buftypes: string[], filetypes: string[] }
---@field throttle integer
---@field priority integer
---@field keywords QFBookKeywords

---@class QFBookNotes
---@field open_cmd string | { mode: string, anchor: string }
---@field size string
---@field filetype string
---@field current_project { enabled: boolean, filename: string }

---@class QFbookMarkKeymaps
---@field up string,
---@field down string,
---@field move_up string,
---@field move_down string
---@field load_all string
---@field select string
---@field zoom string

---@class WindowConfig
---@field notify { enabled: boolean, mark: boolean, plugin: boolean }
---@field quickfix { enabled: boolean, copen: string, lopen: string, theme: {  enabled: boolean, maxheight: integer, limit: integer, highlight: boolean  }, actions: { auto_center: boolean, auto_unfold: boolean } }
---@field mark { anchor: string, keymap: QFbookMarkKeymaps, on_send: function | nil }
---@field note QFBookNotes

---@class QFBookKeymapQfSpec
---@field toggle_open string | string[]
---@field add_item string | string[]

---@class QFBookItemOpenMode
---@field keys string | string[]
---@field auto_close boolean

---@class QFBookKeymapOpenItem
---@field default QFBookItemOpenMode
---@field split  QFBookItemOpenMode
---@field vsplit QFBookItemOpenMode
---@field tab QFBookItemOpenMode

---@class QFBookKeymapMoveWindow
---@field move_up string | string[]
---@field move_down string | string[]
---@field rotate_layout_note string | string[]

---@class QFBookKeymapMoveQFlist
---@field next string | string[]
---@field prev string | string[]
---@field next_hist string | string[]
---@field prev_hist string | string[]

---@class QFBookKeymapMoveMark
---@field next string | string[]
---@field prev string | string[]

---@class QFBookKeymapMoveBuffers
---@field next string | string[]
---@field prev string | string[]

---@class QFBookKeymapMove
---@field quicklist QFBookKeymapMoveQFlist
---@field window QFBookKeymapMoveWindow
---@field mark QFBookKeymapMoveMark

---@class QFBookKeymapTrouble
---@field enabled boolean
---@field toggle_qflist string | string[]
---@field toggle_loclist string | string[]

---@class QFBookKeymapIntegrationSpec
---@field enabled boolean
---@field toggle string | string[]

---@class QFBookKeymapCMDPattern
---@field key string
---@field cmd string | function
---@field desc string
---@field mode? KeyMode
---@field buffer? boolean

---@class QFBookKeymapCMDLineStrings
---@field enabled boolean
---@field commands QFBookKeymapCMDPattern[]

---@class QFBookKeymapNotes
---@field toggle_local_note string | string[]
---@field toggle_global_note string | string[]

---@class QFBookKeymapIntegrations
---@field trouble QFBookKeymapTrouble
---@field grugfar QFBookKeymapIntegrationSpec
---@field copyline QFBookKeymapIntegrationSpec
---@field cmdline_strings QFBookKeymapCMDLineStrings

---@class QFBookKeymapMarkHarpoon
---@field mark_1 string | string[],
---@field mark_2 string | string[],
---@field mark_3 string | string[],
---@field mark_4 string | string[],
---@field mark_5 string | string[],
---@field mark_6 string | string[],
---@field mark_7 string | string[],
---@field mark_8 string | string[],
---@field mark_9 string | string[],

---@class QFBookKeymapActions
---@field delete_mark string | string[]
---@field delete_mark_buffer string | string[]
---@field delete_item string | string[]
---@field delete_item_all string | string[]
---@field rename_title string | string[]
---@field save_or_load string | string[]
---@field mark_win_open string | string[]
---@field mark string | string[]
---@field fix string | string[]
---@field debug string | string[]
---@field note string | string[]
---@field harpoon QFBookKeymapMarkHarpoon
---@field buffers string

---@class QFBookmarkKeymap
---@field disable_all boolean
---@field actions QFBookKeymapActions
---@field navigation QFBookKeymapMove
---@field open_item QFBookKeymapOpenItem
---@field quickfix QFBookKeymapQfSpec
---@field loclist QFBookKeymapQfSpec
---@field integrations QFBookKeymapIntegrations
---@field note QFBookKeymapNotes

---@class QFBookmarkConfig
---@field save_dir string
---@field picker "fzf-lua" | "default"
---@field extmarks QFBookExtermarks
---@field window WindowConfig
---@field keymaps QFBookmarkKeymap
---@field ns? integer
---@field sign_group? string

---@class QFBookKeys
---@field desc string
---@field func string | function
---@field keys string | string[] | nil
---@field mode string | string[]
---@field from_user? boolean

---@class QFBookUiCfg
---@field win integer?
---@field buf integer?
---@field augroup string?

---@class QFBookHighlightCfg
---@field higroup? { fromTo: string, attr: "fg"|"bg"}
---@field darken? { amount: integer, fromTo: string, attr: "fg"|"bg"}
---@field tint? { amount: integer, fromTo: string, attr: "fg"|"bg"}

---@class QFBookHighlight
---@field fg? QFBookHighlightCfg
---@field bg? QFBookHighlightCfg
---@field bold? boolean
