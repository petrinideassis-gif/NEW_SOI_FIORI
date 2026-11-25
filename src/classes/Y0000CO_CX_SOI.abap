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
*  - IF_T100_DYN_MSG and the constructor are inherited from
*    CX_RAP_QUERY_PROVIDER (declaring the interface again is rejected),
*    so RAISE EXCEPTION ... MESSAGE ... WITH works without own code;
*    the text is passed as message 00/398 (& & & &)
*----------------------------------------------------------------------*
class y0000co_cx_soi definition
  public
  inheriting from cx_rap_query_provider
  final
  create public.

  public section.

endclass.


class y0000co_cx_soi implementation.

endclass.
