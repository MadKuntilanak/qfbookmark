---@alias KeyMode "n" | "x" | "i" | "t" | "o"
---@alias QFBookCurrentState "Local" | "Global"
---@alias QFBookListType "loclist" | "quickfix" | "none" | "trouble_mode" | "trouble_source"
---@alias QFBookListProviders "buffers" | "mark" | "quickfix" | "loclist" | "note"
---@alias QFBookMarkMode "MARK" | "DEBUG" | "NOTE" | "FIX"
---@alias QFBookState "Save Qflist" | "Save Loclist" | "Load"

---@alias QFBookmarkBufferMarkGroup table<string, QFbookBufferMarkEntry>
---@alias QFBookmarkBufferMark table<QFBookMarkMode, QFBookmarkBufferMarkGroup>

---@alias QFBookmarkUiPreview { win: integer, buf: integer, wincfg?: table, namespace: string, fullscreen?: boolean }
---@alias QFBookmarkUiPopup { win: integer, buf: integer, preview?: QFBookmarkUiPreview, namespace: string}

---@alias QFBookmarkUiSaveCfg {
--- title: string,
--- target_path: string,
--- is_loc: boolean,
--- cb: function,
--- for_what: "save"|"rename" }

---@alias QFBookmarkEntry {
--- hval: string,
--- id: integer,
--- start_line: integer,
--- line_count: integer,
--- mark: QFbookBufferMarkEntry, }

---@alias QFBookmarkUiPopupCfg {
--- contents: table,
--- content_map: table<integer, QFBookmarkEntry>,
--- win_opts: WinCfg,
--- original_popup_mark_width: integer,
--- original_popup_buffer_width: integer,
--- display_lines: string[],
--- popup?: QFBookmarkUiPopup,
--- is_harpoon?: boolean,
--- is_buffers?: boolean,
--- is_mark_annotation?: boolean,
--- is_note?: boolean,
--- is_select_sink?: boolean,
--- active: string,
--- save?: QFBookmarkUiSaveCfg,
--- selected: table<string, boolean>,
--- buffer_selected: table<integer, boolean>,
--- last_buf: integer,
--- keys_shortcuts: string[],
--- on_submit: function,
--- on_cancel: function,
--- _opts: table,
--- data_annotation?: { chunk: QFbookBufferMarkEntry, load_chunk: boolean } }

---@alias QFBookmarkWinCfg {
--- save: QFBookUiCfg,
--- save_footer: QFBookUiCfg,
--- mark_preview: QFBookUiCfg,
--- mark: QFBookUiCfg,
--- buffer: QFBookUiCfg,
--- note: QFBookUiCfg,
--- mark_annotation: QFBookUiCfg,
--- mark_annotation_preview: QFBookUiCfg,
--- select_category: QFBookUiCfg }

---@class QFBookmarkContextQFlist
---@field name string
---@field bufnr? integer

---@class QFBookmarkLists
---@field title string
---@field items table[]
---@field id? integer
---@field context? QFBookmarkContextQFlist | string
---@field trouble_mode? string
---@field trouble_source? string

---@class QFBookListResults
---@field quickfix QFBookmarkLists
---@field location QFBookmarkLists

---@class QFBookSpec
---@field icon string
---@field hl_group string

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
---@field category string
---@field sign_category string
---@field inserted_at integer
---@field fn_name string
---@field note string[]
---@field id integer
---@field key integer
---@field start_line integer | nil
---@field end_line integer | nil
---@field sign_ids integer[] | nil
---@field original_span integer | nil

---@class QFBookmarkExtermarkAnnotationRange
---@field start_row integer
---@field start_col integer
---@field end_row integer
---@field end_col integer

---@class QFbookPreviewOpts
---@field default_template? string
---@field send_target? string
---@field ns? integer
---@field is_multi? boolean
---@field items? {bufnr: integer, key: integer, category: string}

---@class QFBookmarkExtermarks
---@field excluded { buftypes: string[], filetypes: string[] }
---@field throttle integer
---@field priority integer
---@field keywords QFBookKeywords

---@class QFBookmarkMarkKeymaps
---@field move_item_up string | string[]
---@field move_item_down string | string[]
---@field pick_master string | string[]
---@field zoom string | string[]
---@field toggle_open string | string[]
---@field del_mark string | string[]
---@field del_mark_buffer string | string[]
---@field harpoon QFBookKeymapMarkHarpoon
---@field save_annotation string | string[]
---@field preview_context string | string[]
---@field edit_context string | string[]
---@field add_mark string | string[]
---@field add_fix string | string[]
---@field add_debug string | string[]
---@field add_mark_annotation string | string[]
---@field integrations QFBookKeymapIntegrations

---@class QFBookmarkKeymapQfSpec
---@field toggle_open string | string[]
---@field add_item string | string[]

---@class QFBookmarkQuickfixKeymaps
---@field rename_title string | table[]
---@field next_hist string | string[]
---@field prev_hist string | string[]
---@field add_item_to_loc string | string[]
---@field add_item_to_qf string | string[]
---@field open_toggle_loc string | string[]
---@field open_toggle_qf string | string[]
---@field save_or_load string | string[]
---@field layout_up string | string[]
---@field layout_down string | string[]
---@field integrations QFBookKeymapIntegrations

---@class QFbookMasterOpts
---@field orig string,
---@field dir string,
---@field basename string,
---@field project string,
---@field branch string,
---@field tag string,
---@field text string,

---@class QFBookmarkLines
---@field lines string[]
---@field selection string
---@field csrow integer
---@field cscol integer
---@field cerow integer
---@field cecol integer

---@class QFBookWindowNotes
---@field enabled boolean
---@field width integer
---@field height integer
---@field mode string
---@field anchor string
---@field wrap boolean
---@field insert_to_note {enabled: boolean, line_placeholder: string, templates: table<string, QFBookNoteIntegrationsTemplates>}
---@field current_project { enabled: boolean, filename: string }

---@class QFBookWindowMarkAnnotationKeymaps
---@field accept string

---@class QFBookWindowMarkAnnotation
---@field keymaps QFBookWindowMarkAnnotationKeymaps

---@class QFBookWindowMark
---@field enabled boolean
---@field anchor string
---@field allow_number boolean
---@field preview_fullscreen boolean
---@field context_templates {separator?: string, default: string, handler: table<string, table>}
---@field sinks {default: string, handler: table<string, function|string, string>}
---@field actions { win_resized: boolean }

---@class QFBookItemOpenMode
---@field auto_close boolean

---@class QFBookWindowQuickfixActions
---@field auto_center boolean
---@field auto_unfold boolean
---@field copen string
---@field lopen string
---@field split QFBookItemOpenMode
---@field vsplit QFBookItemOpenMode
---@field default QFBookItemOpenMode
---@field tab QFBookItemOpenMode

---@class QFBookWindowQuickfix
---@field enabled boolean
---@field theme { enabled: boolean, maxheight: integer, limit: integer, highlight: boolean  }
---@field actions  QFBookWindowQuickfixActions

---@class QFBookWindowBuffers
---@field enabled boolean
---@field allow_number boolean
---@field actions { win_resized: boolean }

---@class QFBookmarkWindowCfg
---@field notify { note: boolean, mark: boolean, plugin: boolean, buffers: boolean }
---@field quickfix QFBookWindowQuickfix
---@field mark QFBookWindowMark
---@field buffers QFBookWindowBuffers
---@field note QFBookWindowNotes

---@class QFBookKeymapMoveMark
---@field next string | string[]
---@field prev string | string[]

---@class QFBookKeymapMoveBuffers
---@field next string | string[]
---@field prev string | string[]

---@class QFBookKeymapTroubleIntegration
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
---@field buffer? integer

---@class QFBookKeymapCustomIntegration
---@field enabled boolean
---@field commands QFBookKeymapCMDPattern[]

---@class QFBookmarkNoteKeymaps
---@field toggle_open_global string | string[]
---@field toggle_open_local string | string[]
---@field layout_rotate string | string[]
---@field integrations QFBookKeymapCustomIntegrations

---@class QFBookKeymapMarkOpenItem
---@field default string | string[]

---@class QFBookKeymapIntegrations
---@field trouble? QFBookKeymapTroubleIntegration
---@field grugfar? QFBookKeymapIntegrationSpec
---@field copyline? QFBookKeymapIntegrationSpec
---@field custom? QFBookKeymapCustomIntegration

---@class QFBookNoteIntegrationsTemplates
---@field target string
---@field description string
---@field templates string | function

---@class QFBookKeymapCustomIntegrations
---@field custom? QFBookKeymapCustomIntegration

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

---@class QFBookmarkKeymapActions
---@field quit string | string[]
---@field up string | string[]
---@field down string | string[]
---@field default string | string[]
---@field split  string | string[]
---@field vsplit string | string[]
---@field tab string | string[]
---@field next_item string | string[]
---@field prev_item string | string[]
---@field del_item string | table[]
---@field del_item_all string | table[]
---@field toggle_select string | string[]
---@field diselect_all string | string[]
---@field show_help string
---@field scroll_preview_up string | string[]
---@field scroll_preview_down string | string[]
---@field scroll_preview_up_fast string | string[]
---@field scroll_preview_down_fast string | string[]

---@class QFBookmarkBuffersKeymaps
---@field toggle_open string | string[]
---@field integrations QFBookKeymapCustomIntegrations

---@class QFBookmarkKeymap
---@field actions QFBookmarkKeymapActions
---@field mark QFBookmarkMarkKeymaps
---@field quickfix QFBookmarkQuickfixKeymaps
---@field note QFBookmarkNoteKeymaps
---@field buffers QFBookmarkBuffersKeymaps

---@class QFBookmarkConfig
---@field save_dir string
---@field picker "fzf-lua" | "default"
---@field extmarks QFBookmarkExtermarks
---@field window QFBookmarkWindowCfg
---@field keymaps QFBookmarkKeymap
---@field ns? integer
---@field sign_group? string

---@class QFBookKeys
---@field desc string
---@field func string | function
---@field keys string | string[] | nil
---@field mode string | string[]
---@field from_user? boolean
---@field buffer? integer

---@class QFBookUiCfg
---@field win integer?
---@field buf integer?
---@field augroup string?
---@field namespace string?

---@class QFBookHighlightCfg
---@field higroup? { fromTo: string, attr: "fg"|"bg"}
---@field darken? { amount: integer, fromTo: string, attr: "fg"|"bg"}
---@field tint? { amount: integer, fromTo: string, attr: "fg"|"bg"}

---@class QFBookHighlight
---@field fg? QFBookHighlightCfg
---@field bg? QFBookHighlightCfg
---@field bold? boolean
