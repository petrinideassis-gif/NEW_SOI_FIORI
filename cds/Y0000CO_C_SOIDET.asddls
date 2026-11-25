@EndUserText.label: 'SOI report - breakdown'
@ObjectModel.query.implementedBy: 'ABAP:Y0000CO_CL_SOI_QUERY'
@UI.headerInfo: { typeName:       'Breakdown Row',
                  typeNamePlural: 'Breakdown',
                  title:          { type: #STANDARD, value: 'RowType' } }
define custom entity Y0000CO_C_SOIDET
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
      @UI.facet: [
        { id:            'Totals',
          purpose:       #STANDARD,
          type:          #IDENTIFICATION_REFERENCE,
          label:         'Totals',
          position:      10 },
        { id:            'LineItems',
          purpose:       #STANDARD,
          type:          #LINEITEM_REFERENCE,
          label:         'Line Items',
          position:      20,
          targetElement: '_Items' } ]
      @UI.lineItem: [{ position: 20, importance: #HIGH }]
      @UI.identification: [{ position: 10 }]
      @EndUserText.label: 'Cost Center'
  key CostCenter       : kostl;

      @UI.lineItem: [{ position: 30, importance: #HIGH }]
      @UI.identification: [{ position: 20 }]
      @EndUserText.label: 'Order'
  key OrderNumber      : aufnr;

      @UI.lineItem: [{ position: 40, importance: #HIGH }]
      @UI.identification: [{ position: 30 }]
      @UI.textArrangement: #TEXT_LAST
      @ObjectModel.text.element: [ 'CostElementText' ]
      @EndUserText.label: 'Cost Element'
  key CostElement      : kstar;

      @UI.lineItem: [{ position: 50, importance: #HIGH }]
      @UI.textArrangement: #TEXT_LAST
      @ObjectModel.text.element: [ 'ComponentText' ]
      @EndUserText.label: 'Formula Component'
  key ComponentLine    : y0000co_soiline;

      @UI.lineItem: [{ position: 10 }]
      @EndUserText.label: 'Type'
      RowType          : abap.char(20);

      @EndUserText.label: 'Cost Element Text'
      CostElementText  : abap.char(50);

      @EndUserText.label: 'Component Text'
      ComponentText    : abap.char(35);

      @UI.lineItem: [{ position: 60 }]
      @EndUserText.label: 'Operator'
      Operator         : abap.char(1);

      @UI.lineItem: [{ position: 70 }]
      @UI.textArrangement: #TEXT_LAST
      @ObjectModel.text.element: [ 'CostCenterCategoryText' ]
      @EndUserText.label: 'Cost Center Category'
      CostCenterCategory : kosar;

      @EndUserText.label: 'Cost Center Category Text'
      CostCenterCategoryText : abap.char(50);

      @UI.lineItem: [{ position: 80 }]
      @UI.textArrangement: #TEXT_LAST
      @ObjectModel.text.element: [ 'FunctionalAreaText' ]
      @EndUserText.label: 'Functional Area'
      FunctionalArea   : fkber;

      @EndUserText.label: 'Functional Area Text'
      FunctionalAreaText : abap.char(50);

      @UI.lineItem: [{ position: 100, importance: #HIGH }]
      @UI.identification: [{ position: 40 }]
      @EndUserText.label: 'Total'
      @Semantics.amount.currencyCode: 'Currency'
      TotalAmount      : abap.curr(15,2);

      @UI.lineItem: [{ position: 110 }]
      @UI.identification: [{ position: 50 }]
      @EndUserText.label: 'Comparison Total'
      @Semantics.amount.currencyCode: 'Currency'
      CompareAmount    : abap.curr(15,2);

      @UI.lineItem: [{ position: 120 }]
      @UI.identification: [{ position: 60 }]
      @EndUserText.label: 'Difference'
      @Semantics.amount.currencyCode: 'Currency'
      DifferenceAmount : abap.curr(15,2);

      @UI.lineItem: [{ position: 130 }]
      @UI.identification: [{ position: 70 }]
      @EndUserText.label: 'Difference %'
      DifferencePercent : abap.dec(9,2);

      @UI.lineItem: [{ position: 210 }]
      @EndUserText.label: 'Period 01'
      @Semantics.amount.currencyCode: 'Currency'
      Period01         : abap.curr(15,2);

      @UI.lineItem: [{ position: 220 }]
      @EndUserText.label: 'Period 02'
      @Semantics.amount.currencyCode: 'Currency'
      Period02         : abap.curr(15,2);

      @UI.lineItem: [{ position: 230 }]
      @EndUserText.label: 'Period 03'
      @Semantics.amount.currencyCode: 'Currency'
      Period03         : abap.curr(15,2);

      @UI.lineItem: [{ position: 240 }]
      @EndUserText.label: 'Period 04'
      @Semantics.amount.currencyCode: 'Currency'
      Period04         : abap.curr(15,2);

      @UI.lineItem: [{ position: 250 }]
      @EndUserText.label: 'Period 05'
      @Semantics.amount.currencyCode: 'Currency'
      Period05         : abap.curr(15,2);

      @UI.lineItem: [{ position: 260 }]
      @EndUserText.label: 'Period 06'
      @Semantics.amount.currencyCode: 'Currency'
      Period06         : abap.curr(15,2);

      @UI.lineItem: [{ position: 270 }]
      @EndUserText.label: 'Period 07'
      @Semantics.amount.currencyCode: 'Currency'
      Period07         : abap.curr(15,2);

      @UI.lineItem: [{ position: 280 }]
      @EndUserText.label: 'Period 08'
      @Semantics.amount.currencyCode: 'Currency'
      Period08         : abap.curr(15,2);

      @UI.lineItem: [{ position: 290 }]
      @EndUserText.label: 'Period 09'
      @Semantics.amount.currencyCode: 'Currency'
      Period09         : abap.curr(15,2);

      @UI.lineItem: [{ position: 300 }]
      @EndUserText.label: 'Period 10'
      @Semantics.amount.currencyCode: 'Currency'
      Period10         : abap.curr(15,2);

      @UI.lineItem: [{ position: 310 }]
      @EndUserText.label: 'Period 11'
      @Semantics.amount.currencyCode: 'Currency'
      Period11         : abap.curr(15,2);

      @UI.lineItem: [{ position: 320 }]
      @EndUserText.label: 'Period 12'
      @Semantics.amount.currencyCode: 'Currency'
      Period12         : abap.curr(15,2);

      @UI.lineItem: [{ position: 330 }]
      @UI.identification: [{ position: 80 }]
      @EndUserText.label: 'Periods 13-16'
      @Semantics.amount.currencyCode: 'Currency'
      SpecialPeriods   : abap.curr(15,2);

      Currency         : waers;

      _Items           : association [0..*] to Y0000CO_C_SOIITM
                         on  _Items.SoiVersion       = $projection.SoiVersion
                         and _Items.FiscalYear       = $projection.FiscalYear
                         and _Items.CompanyCode      = $projection.CompanyCode
                         and _Items.ValueType        = $projection.ValueType
                         and _Items.Version          = $projection.Version
                         and _Items.PeriodFrom       = $projection.PeriodFrom
                         and _Items.PeriodTo         = $projection.PeriodTo
                         and _Items.CompareYear      = $projection.CompareYear
                         and _Items.CompareVersion   = $projection.CompareVersion
                         and _Items.CompareValueType = $projection.CompareValueType
                         and _Items.SoiLine          = $projection.SoiLine
                         and _Items.CostCenter       = $projection.CostCenter
                         and _Items.OrderNumber      = $projection.OrderNumber
                         and _Items.CostElement      = $projection.CostElement
                         and _Items.ComponentLine    = $projection.ComponentLine;
}
