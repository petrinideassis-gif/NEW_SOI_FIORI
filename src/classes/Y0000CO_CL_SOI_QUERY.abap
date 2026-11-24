*----------------------------------------------------------------------*
* Description : Query provider for the SOI Fiori preview (stage 1 stub)
*----------------------------------------------------------------------*
* ABAP Name     : Y0000CO_CL_SOI_QUERY
* Author        : <SAP user ID>
* Date          : 24.11.2026
* Reference No. : <CHG0000000 / CTASK0000000>
*----------------------------------------------------------------------*
*  Changes     (internal Version: Documentation/Info on line level)    *
*----------------------------------------------------------------------*
*  Date       Name    internal    Transp.No. Description               *
*                    -Version-    Refer. No.                           *
*                                                                      *
*----------------------------------------------------------------------*
*  Purpose
*  Fills the custom entity Y0000CO_C_SOILINE for the Fiori preview of
*  the Statement of Income (SOI).
*
*  Stage 1 (this version) is a stub: it returns the real SOI lines and
*  texts of the selected version from the SOI customizing, with a zero
*  amount. It checks the plumbing (filter bar, mandatory fields,
*  defaults, columns, sorting, paging) before the SOI engine is
*  connected.
*
*  Typical business use:
*  Controllers open the SOI preview, select version, year and company
*  code, and read the statement lines.
*
*  Main Steps
*  1. Read the filter values of the request
*  2. Read the SOI lines and texts of the selected version
*  3. Build the result rows (amount zero in stage 1)
*  4. Apply sorting and paging, return the rows and the total count
*
*  Important technical notes from development:
*  - Controlling area (KOKRS) is fixed to '2000' (not needed in stage 1)
*  - Text lookup prefers the logon language and falls back to 'E', as
*    in Y0000CO_SOI_NEW, so a missing translation never drops a line
*  - No authorization check in stage 1; stage 2 adds it as the first
*    statement of SELECT, together with the engine call
*  - Comments must stay inside METHOD ... ENDMETHOD: the class editor
*    rejects comments between method implementations
*  - The framework expects sorting and paging to be read by the query
*    provider; both are applied in memory (a few dozen SOI lines)
*  - CX_RAP_QUERY_PROVIDER is abstract and cannot be raised;
*    CX_RAP_QUERY_FILTER_NO_RANGE is passed through instead
*----------------------------------------------------------------------*
class y0000co_cl_soi_query definition
  public
  final
  create public.

  public section.
    interfaces if_rap_query_provider.

  private section.

*---------------------------------------------------------------------*
* Filter values of one request
*---------------------------------------------------------------------*
* Only the first single value of each filter is used in stage 1; the
* entity has no ranges or multi-value filters yet.
*---------------------------------------------------------------------*
    types:
      begin of ty_filter,
        soivar type y0000co_nsoi00-soivar,
        gjahr  type gjahr,
        bukrs  type bukrs,
        wrttp  type wrttp,
        versn  type versn,
      end of ty_filter.

*---------------------------------------------------------------------*
* Result table type
*---------------------------------------------------------------------*
* A named table type is needed: generic table types cannot be used in
* RETURNING parameters.
*---------------------------------------------------------------------*
    types:
      tt_result type standard table of y0000co_c_soiline with empty key.

    constants:
      gc_fallback_langu type sy-langu value 'E'.

    methods:
      read_filter
        importing io_request       type ref to if_rap_query_request
        returning value(rs_filter) type ty_filter
        raising   cx_rap_query_filter_no_range,
      read_lines
        importing is_filter        type ty_filter
        returning value(rt_result) type tt_result,
      sort_result
        importing io_request type ref to if_rap_query_request
        changing  ct_result  type tt_result,
      page_result
        importing io_request     type ref to if_rap_query_request
                  it_result      type tt_result
        returning value(rt_page) type tt_result.

endclass.


class y0000co_cl_soi_query implementation.

  method if_rap_query_provider~select.
*---------------------------------------------------------------------*
* Select: entry point called by the RAP framework
*---------------------------------------------------------------------*
* The framework calls this for the data request and, separately, for
* a count-only request. Both are answered from the same result table.
* CX_RAP_QUERY_FILTER_NO_RANGE from READ_FILTER is not caught: it
* passes through to the framework, which reports it.
*---------------------------------------------------------------------*

    data(ls_filter) = read_filter( io_request ).
    data(lt_result) = read_lines( ls_filter ).

    sort_result(
      exporting io_request = io_request
      changing  ct_result  = lt_result ).

    data(lt_page) = page_result( io_request = io_request
                                 it_result  = lt_result ).

    if io_request->is_data_requested( ) = abap_true.
      io_response->set_data( lt_page ).
    endif.

    if io_request->is_total_numb_of_rec_requested( ) = abap_true.
      io_response->set_total_number_of_records( lines( lt_result ) ).
    endif.

  endmethod.


  method read_filter.
*---------------------------------------------------------------------*
* Read the filter values of the request
*---------------------------------------------------------------------*
* Defaults match the entity annotations and the classic report
* (SOIVAR STD, value type 04, version 000), so a request without them
* still behaves like the report with its defaults. Filter element
* names arrive in upper case (SOIVERSION, FISCALYEAR, ...).
*---------------------------------------------------------------------*

    data(lt_ranges) = io_request->get_filter( )->get_as_ranges( ).

    rs_filter-soivar = 'STD'.
    rs_filter-wrttp  = '04'.
    rs_filter-versn  = '000'.

    loop at lt_ranges assigning field-symbol(<ls_range>).
      read table <ls_range>-range index 1 into data(ls_value).
      if sy-subrc <> 0.
        continue.
      endif.

      case to_upper( <ls_range>-name ).
        when 'SOIVERSION'.
          rs_filter-soivar = ls_value-low.
        when 'FISCALYEAR'.
          rs_filter-gjahr = ls_value-low.
        when 'COMPANYCODE'.
          rs_filter-bukrs = ls_value-low.
        when 'VALUETYPE'.
          rs_filter-wrttp = ls_value-low.
        when 'VERSION'.
          rs_filter-versn = ls_value-low.
      endcase.
    endloop.

  endmethod.


  method read_lines.
*---------------------------------------------------------------------*
* Read the SOI lines and texts of one version
*---------------------------------------------------------------------*
* Every SELECT is restricted to the selected version: reading the
* customizing without SOIVAR would mix the rows of all versions.
* The texts are read INTO TABLE @DATA(...) because a SELECT into a
* pre-typed table maps by position, not by name (see the note in
* Y0000CO_SOI_NEW, where this caused blank texts).
*---------------------------------------------------------------------*

    select soiline, outline
      from y0000co_nsoi01
      where soivar = @is_filter-soivar
      order by outline
      into table @data(lt_lines).

    if lt_lines is initial.
      return.
    endif.

    select soiline, spras, text
      from y0000co_nsoi01t
      for all entries in @lt_lines
      where soivar  = @is_filter-soivar
        and soiline = @lt_lines-soiline
        and spras in ( @sy-langu, @gc_fallback_langu )
      into table @data(lt_texts).

*---------------------------------------------------------------------*
* Company code currency
*---------------------------------------------------------------------*
* Amounts are zero in stage 1, but the amount column still needs its
* currency for the Fiori table to render it.
*---------------------------------------------------------------------*
    select single waers
      from t001
      where bukrs = @is_filter-bukrs
      into @data(lv_waers).

    loop at lt_lines assigning field-symbol(<ls_line>).
      data(lv_text) = value y0000co_nsoi01t-text( ).

      read table lt_texts into data(ls_text)
        with key soiline = <ls_line>-soiline
                 spras   = sy-langu.
      if sy-subrc <> 0.
        read table lt_texts into ls_text
          with key soiline = <ls_line>-soiline
                   spras   = gc_fallback_langu.
      endif.

      if sy-subrc = 0.
        lv_text = ls_text-text.
      endif.

      append value #(
        soiversion  = is_filter-soivar
        fiscalyear  = is_filter-gjahr
        companycode = is_filter-bukrs
        valuetype   = is_filter-wrttp
        version     = is_filter-versn
        soiline     = <ls_line>-soiline
        soilinetext = lv_text
        outline     = <ls_line>-outline
        totalamount = 0
        currency    = lv_waers ) to rt_result.
    endloop.

  endmethod.


  method sort_result.
*---------------------------------------------------------------------*
* Apply the requested sort order
*---------------------------------------------------------------------*
* Without a requested sort the table keeps the outline order from
* READ_LINES, which is the statement order. Sort element names are
* the entity element names and match the component names of the
* result structure, so they can drive a dynamic SORT.
*---------------------------------------------------------------------*

    data(lt_sort_elements) = io_request->get_sort_elements( ).

    if lt_sort_elements is initial.
      return.
    endif.

    data(lt_sort_order) = value abap_sortorder_tab(
      for ls_sort in lt_sort_elements
      ( name       = to_upper( ls_sort-element_name )
        descending = ls_sort-descending ) ).

    sort ct_result by (lt_sort_order).

  endmethod.


  method page_result.
*---------------------------------------------------------------------*
* Apply the requested page ($skip / $top)
*---------------------------------------------------------------------*
* Paging is applied in memory: the result is a few dozen SOI lines,
* not a database table. PAGE_SIZE_UNLIMITED means no $top was sent.
*---------------------------------------------------------------------*

    data(lv_offset)    = conv i( io_request->get_paging( )->get_offset( ) ).
    data(lv_page_size) = conv i( io_request->get_paging( )->get_page_size( ) ).

    if lv_page_size = if_rap_query_paging=>page_size_unlimited.
      rt_page = value #( for ls_row in it_result from lv_offset + 1 ( ls_row ) ).
      return.
    endif.

    rt_page = value #( for ls_row in it_result
                       from lv_offset + 1
                       to   lv_offset + lv_page_size
                       ( ls_row ) ).

  endmethod.

endclass.
