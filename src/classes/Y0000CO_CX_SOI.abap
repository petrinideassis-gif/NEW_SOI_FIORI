*----------------------------------------------------------------------*
* Description : Error raised by the SOI Fiori preview query
*----------------------------------------------------------------------*
* ABAP Name     : Y0000CO_CX_SOI
* Author        : <SAP user ID>
* Date          : 25.11.2026
* Reference No. : <CHG0000000 / CTASK0000000>
*----------------------------------------------------------------------*
*  Changes     (internal Version: Documentation/Info on line level)    *
*----------------------------------------------------------------------*
*  Date       Name    internal    Transp.No. Description               *
*                    -Version-    Refer. No.                           *
*                                                                      *
*----------------------------------------------------------------------*
*  Purpose
*  Carries a blocking error of the SOI engine (wrong period range,
*  company code not in controlling area 2000, no customizing, ...)
*  from the query provider Y0000CO_CL_SOI_QUERY to the Fiori app,
*  which shows its text as an error message instead of an empty table.
*
*  Typical business use:
*  A controller enters an invalid selection in the SOI preview and is
*  told why nothing is shown.
*
*  Main Steps
*  1. The query provider raises it with RAISE EXCEPTION ... MESSAGE
*  2. The RAP framework returns its T100 text as the OData error
*
*  Important technical notes from development:
*  - Inherits from CX_RAP_QUERY_PROVIDER, the exception declared by
*    IF_RAP_QUERY_PROVIDER~SELECT (that class is abstract and cannot be
*    raised itself)
*  - IF_T100_DYN_MSG allows RAISE EXCEPTION ... MESSAGE ... WITH, so
*    the text can be passed as message 00/398 (& & & &)
*----------------------------------------------------------------------*
class y0000co_cx_soi definition
  public
  inheriting from cx_rap_query_provider
  final
  create public.

  public section.
    interfaces if_t100_dyn_msg.

    methods constructor
      importing
        textid   like if_t100_message=>t100key optional
        previous like previous optional.

endclass.


class y0000co_cx_soi implementation.

  method constructor ##ADT_SUPPRESS_GENERATION.
*---------------------------------------------------------------------*
* Standard constructor of a T100 exception class
*---------------------------------------------------------------------*
* Without a TEXTID the default T100 key is used; RAISE EXCEPTION ...
* MESSAGE overwrites it with the message given there.
*---------------------------------------------------------------------*
    super->constructor( previous = previous ).

    clear me->textid.
    if textid is initial.
      if_t100_message~t100key = if_t100_message=>default_textid.
    else.
      if_t100_message~t100key = textid.
    endif.
  endmethod.

endclass.
