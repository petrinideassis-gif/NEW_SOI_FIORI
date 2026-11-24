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


*----------------------------------------------------------------------*
*  Purpose
*  Fills the custom entity Y0000CO_C_SOILINE for the Fiori preview of
*  the Statement of Income (SOI).
*
*  Stage 1 (this version) is a stub: it returns the real SOI lines and
*  texts of the selected version from the SOI customizing, with a zero
*  amount. It checks the plumbing (filter bar, mandatory fields,
*  defaults, columns, paging) before the SOI engine is connected.
*
*  Typical business use:
*  Controllers open the SOI preview, select version, year and company
*  code, and read the statement lines.
*
*  Main Steps
*  1. Read the filter values of the request
*  2. Read the SOI lines and texts of the selected version
*  3. Build the result rows (amount zero in stage 1)
*  4. Apply paging and return the rows and the total count
*
*  Important technical notes from development:
*  - Controlling area (KOKRS) is fixed to '2000' (not needed in stage 1)
*  - Text lookup prefers the logon language and falls back to 'E', as
*    in Y0000CO_SOI_NEW, so a missing translation never drops a line
*  - Stage 2 adds the authorization check as the first statement and
*    the engine call; no authorization check exists in stage 1
*  - Filter element names arrive in upper case (SOIVERSION, ...)
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
        returning value(rt_result) type tt_result.

endclass.


class y0000co_cl_soi_query implementation.

*---------------------------------------------------------------------*
* Select: entry point called by the RAP framework
*---------------------------------------------------------------------*
* The framework calls this for the data request and, separately, for
* a count-only request. Both are answered from the same result table.
*---------------------------------------------------------------------*
  method if_rap_query_provider~select.

    try.
        data(ls_filter) = read_filter( io_request ).
      catch cx_rap_query_filter_no_range into data(lx_filter).
        raise exception type cx_rap_query_provider
          exporting
            previous = lx_filter.
    endtry.

    data(lt_result) = read_lines( ls_filter ).

*   Paging is applied in memory: the result is a few dozen SOI lines,
*   not a database table.
    data(lv_offset)    = io_request->get_paging( )->get_offset( ).
    data(lv_page_size) = io_request->get_paging( )->get_page_size( ).

    data lt_page like lt_result.
    if lv_page_size = if_rap_query_paging=>page_size_unlimited.
      lt_page = lt_result.
    else.
      data(lv_from) = lv_offset + 1.
      data(lv_to)   = lv_offset + lv_page_size.
      lt_page = value #( for ls_row in lt_result from lv_from to lv_to ( ls_row ) ).
    endif.

    if io_request->is_data_requested( ) = abap_true.
      io_response->set_data( lt_page ).
    endif.

    if io_request->is_total_numb_of_rec_requested( ) = abap_true.
      io_response->set_total_number_of_records( lines( lt_result ) ).
    endif.

  endmethod.


*---------------------------------------------------------------------*
* Read the filter values of the request
*---------------------------------------------------------------------*
* Defaults match the entity annotations and the classic report
* (SOIVAR STD, value type 04, version 000), so a request without them
* still behaves like the report with its defaults.
*---------------------------------------------------------------------*
  method read_filter.

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


*---------------------------------------------------------------------*
* Read the SOI lines and texts of one version
*---------------------------------------------------------------------*
* Every SELECT is restricted to the selected version: reading the
* customizing without SOIVAR would mix the rows of all versions.
* INTO TABLE @DATA(...) is used for the texts because the SELECT maps
* by position, not by name (see the note in Y0000CO_SOI_NEW).
*---------------------------------------------------------------------*
  method read_lines.

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

*   Company code currency for the amount column (amounts are zero in
*   stage 1, but the column needs its currency).
    select single waers
      from t001
      where bukrs = @is_filter-bukrs
      into @data(lv_waers).

    loop at lt_lines assigning field-symbol(<ls_line>).
      data(lv_text) = value y0000co_nsoi01t-text( ).

      read table lt_texts into data(ls_text)
        with key soiline = <ls_line>-soiline spras = sy-langu.
      if sy-subrc <> 0.
        read table lt_texts into ls_text
          with key soiline = <ls_line>-soiline spras = gc_fallback_langu.
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

endclass.
