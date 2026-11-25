@EndUserText.label: 'SOI report - lines'
@ObjectModel.query.implementedBy: 'ABAP:Y0000CO_CL_SOI_QUERY'
@UI.headerInfo: { typeName:       'SOI Line',
                  typeNamePlural: 'Statement of Income',
                  title:          { type: #STANDARD, value: 'SoiLine' },
                  description:    { type: #STANDARD, value: 'SoiLineText' } }
define root custom entity Y0000CO_C_SOILINE
{
      @UI.facet: [
        { id:            'Totals',
          purpose:       #STANDARD,
          type:          #IDENTIFICATION_REFERENCE,
          label:         'Totals',
          position:      10 },
        { id:            'Breakdown',
          purpose:       #STANDARD,
          type:          #LINEITEM_REFERENCE,
          label:         'Breakdown',
          position:      20,
          targetElement: '_Details' } ]
      @UI.selectionField: [{ position: 10 }]
      @Consumption.filter: { mandatory: true, defaultValue: 'STD' }
  key SoiVersion       : y0000co_soivar;

      @UI.selectionField: [{ position: 20 }]
      @Consumption.filter.mandatory: true
  key FiscalYear       : gjahr;

      @UI.selectionField: [{ position: 30 }]
      @Consumption.filter.mandatory: true
  key CompanyCode      : bukrs;

      @UI.selectionField: [{ position: 40 }]
      @Consumption.filter.defaultValue: '04'
  key ValueType        : wrttp;

      @UI.selectionField: [{ position: 50 }]
      @Consumption.filter.defaultValue: '000'
  key Version          : versn;

      @UI.selectionField: [{ position: 60 }]
      @EndUserText.label: 'Period From'
  key PeriodFrom       : monat;

      @UI.selectionField: [{ position: 70 }]
      @EndUserText.label: 'Period To'
  key PeriodTo         : monat;

      @UI.selectionField: [{ position: 80 }]
      @EndUserText.label: 'Comparison Fiscal Year'
  key CompareYear      : gjahr;

      @UI.selectionField: [{ position: 90 }]
      @EndUserText.label: 'Comparison Version'
  key CompareVersion   : versn;

      @UI.selectionField: [{ position: 100 }]
      @EndUserText.label: 'Comparison Value Type'
  key CompareValueType : wrttp;

      @UI.lineItem: [{ position: 10, importance: #HIGH }]
      @UI.textArrangement: #TEXT_FIRST
      @ObjectModel.text.element: [ 'SoiLineText' ]
  key SoiLine          : y0000co_soiline;

      @EndUserText.label: 'SOI Line Text'
      SoiLineText      : abap.char(35);

      @UI.hidden: true
      Outline          : abap.numc(4);

      @UI.lineItem: [{ position: 20, importance: #HIGH }]
      @UI.identification: [{ position: 10 }]
      @EndUserText.label: 'Total'
      @Semantics.amount.currencyCode: 'Currency'
      TotalAmount      : abap.curr(15,2);

      @UI.lineItem: [{ position: 30 }]
      @UI.identification: [{ position: 20 }]
      @EndUserText.label: 'Comparison Total'
      @Semantics.amount.currencyCode: 'Currency'
      CompareAmount    : abap.curr(15,2);

      @UI.lineItem: [{ position: 40 }]
      @UI.identification: [{ position: 30 }]
      @EndUserText.label: 'Difference'
      @Semantics.amount.currencyCode: 'Currency'
      DifferenceAmount : abap.curr(15,2);

      @UI.lineItem: [{ position: 45 }]
      @UI.identification: [{ position: 40 }]
      @EndUserText.label: 'Difference %'
      DifferencePercent : abap.dec(9,2);

      @UI.lineItem: [{ position: 60 }]
      @EndUserText.label: 'Period 01'
      @Semantics.amount.currencyCode: 'Currency'
      Period01         : abap.curr(15,2);

      @UI.lineItem: [{ position: 70 }]
      @EndUserText.label: 'Period 02'
      @Semantics.amount.currencyCode: 'Currency'
      Period02         : abap.curr(15,2);

      @UI.lineItem: [{ position: 80 }]
      @EndUserText.label: 'Period 03'
      @Semantics.amount.currencyCode: 'Currency'
      Period03         : abap.curr(15,2);

      @UI.lineItem: [{ position: 90 }]
      @EndUserText.label: 'Period 04'
      @Semantics.amount.currencyCode: 'Currency'
      Period04         : abap.curr(15,2);

      @UI.lineItem: [{ position: 100 }]
      @EndUserText.label: 'Period 05'
      @Semantics.amount.currencyCode: 'Currency'
      Period05         : abap.curr(15,2);

      @UI.lineItem: [{ position: 110 }]
      @EndUserText.label: 'Period 06'
      @Semantics.amount.currencyCode: 'Currency'
      Period06         : abap.curr(15,2);

      @UI.lineItem: [{ position: 120 }]
      @EndUserText.label: 'Period 07'
      @Semantics.amount.currencyCode: 'Currency'
      Period07         : abap.curr(15,2);

      @UI.lineItem: [{ position: 130 }]
      @EndUserText.label: 'Period 08'
      @Semantics.amount.currencyCode: 'Currency'
      Period08         : abap.curr(15,2);

      @UI.lineItem: [{ position: 140 }]
      @EndUserText.label: 'Period 09'
      @Semantics.amount.currencyCode: 'Currency'
      Period09         : abap.curr(15,2);

      @UI.lineItem: [{ position: 150 }]
      @EndUserText.label: 'Period 10'
      @Semantics.amount.currencyCode: 'Currency'
      Period10         : abap.curr(15,2);

      @UI.lineItem: [{ position: 160 }]
      @EndUserText.label: 'Period 11'
      @Semantics.amount.currencyCode: 'Currency'
      Period11         : abap.curr(15,2);

      @UI.lineItem: [{ position: 170 }]
      @EndUserText.label: 'Period 12'
      @Semantics.amount.currencyCode: 'Currency'
      Period12         : abap.curr(15,2);

      @UI.lineItem: [{ position: 180 }]
      @UI.identification: [{ position: 50 }]
      @EndUserText.label: 'Periods 13-16'
      @Semantics.amount.currencyCode: 'Currency'
      SpecialPeriods   : abap.curr(15,2);

      @UI.lineItem: [{ position: 190 }]
      @UI.identification: [{ position: 60 }]
      @EndUserText.label: 'Remark'
      Remark           : abap.char(255);

      Currency         : waers;

      _Details         : association [0..*] to Y0000CO_C_SOIDET
                         on  _Details.SoiVersion       = $projection.SoiVersion
                         and _Details.FiscalYear       = $projection.FiscalYear
                         and _Details.CompanyCode      = $projection.CompanyCode
                         and _Details.ValueType        = $projection.ValueType
                         and _Details.Version          = $projection.Version
                         and _Details.PeriodFrom       = $projection.PeriodFrom
                         and _Details.PeriodTo         = $projection.PeriodTo
                         and _Details.CompareYear      = $projection.CompareYear
                         and _Details.CompareVersion   = $projection.CompareVersion
                         and _Details.CompareValueType = $projection.CompareValueType
                         and _Details.SoiLine          = $projection.SoiLine;
}
