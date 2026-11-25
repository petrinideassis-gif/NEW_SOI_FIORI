@EndUserText.label: 'SOI report - line items'
@ObjectModel.query.implementedBy: 'ABAP:Y0000CO_CL_SOI_QUERY'
@UI.headerInfo: { typeName:       'Line Item',
                  typeNamePlural: 'Line Items' }
define custom entity Y0000CO_C_SOIITM
{
      @UI.hidden: true
  key SoiVersion       : y0000co_soivar;

      @UI.hidden: true
  key FiscalYear       : gjahr;

      @UI.hidden: true
  key CompanyCode      : bukrs;

      @UI.hidden: true
  key ValueType        : wrttp;

      @UI.hidden: true
  key Version          : versn;

      @UI.hidden: true
      @EndUserText.label: 'Period From'
  key PeriodFrom       : monat;

      @UI.hidden: true
      @EndUserText.label: 'Period To'
  key PeriodTo         : monat;

      @UI.hidden: true
      @EndUserText.label: 'Comparison Fiscal Year'
  key CompareYear      : gjahr;

      @UI.hidden: true
      @EndUserText.label: 'Comparison Version'
  key CompareVersion   : versn;

      @UI.hidden: true
      @EndUserText.label: 'Comparison Value Type'
  key CompareValueType : wrttp;

      @UI.hidden: true
  key SoiLine          : y0000co_soiline;

      @UI.hidden: true
      @EndUserText.label: 'Cost Center'
  key CostCenter       : kostl;

      @UI.hidden: true
      @EndUserText.label: 'Order'
  key OrderNumber      : aufnr;

      @UI.hidden: true
      @EndUserText.label: 'Cost Element'
  key CostElement      : kstar;

      @UI.hidden: true
      @EndUserText.label: 'Formula Component'
  key ComponentLine    : y0000co_soiline;
      @UI.lineItem: [{ position: 10, importance: #HIGH }]
      @EndUserText.label: 'Data Set'
  key DataSet          : abap.char(10);

      @UI.lineItem: [{ position: 40, importance: #HIGH }]
      @EndUserText.label: 'Document'
  key DocumentNumber   : abap.char(10);

      @UI.lineItem: [{ position: 50 }]
      @EndUserText.label: 'Item'
  key DocumentItem     : abap.numc(3);

      @UI.lineItem: [{ position: 20, importance: #HIGH }]
      @EndUserText.label: 'Period'
  key FiscalPeriod     : abap.numc(3);

      @UI.lineItem: [{ position: 30, importance: #HIGH }]
      @EndUserText.label: 'Posting Date'
      PostingDate      : budat;

      @UI.lineItem: [{ position: 60, importance: #HIGH }]
      @EndUserText.label: 'Amount'
      @Semantics.amount.currencyCode: 'Currency'
      Amount           : abap.curr(15,2);

      @UI.lineItem: [{ position: 70 }]
      @EndUserText.label: 'Text'
      DocumentText     : abap.char(50);

      @UI.lineItem: [{ position: 80 }]
      @EndUserText.label: 'Entered By'
      UserName         : abap.char(12);

      @UI.lineItem: [{ position: 90 }]
      @EndUserText.label: 'Document Date'
      DocumentDate     : bldat;

      @UI.lineItem: [{ position: 100 }]
      @EndUserText.label: 'Entry Date'
      EntryDate        : abap.dats;

      @UI.lineItem: [{ position: 110 }]
      @EndUserText.label: 'Item Fiscal Year'
      ItemFiscalYear   : gjahr;

      @UI.lineItem: [{ position: 120 }]
      @EndUserText.label: 'Item Version'
      ItemVersion      : versn;

      Currency         : waers;
}
