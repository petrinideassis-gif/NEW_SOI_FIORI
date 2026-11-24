@EndUserText.label: 'SOI report - lines'
@ObjectModel.query.implementedBy: 'ABAP:Y0000CO_CL_SOI_QUERY'
@UI.headerInfo: { typeName:       'SOI Line',
                  typeNamePlural: 'Statement of Income',
                  title:          { type: #STANDARD, value: 'SoiLine' },
                  description:    { type: #STANDARD, value: 'SoiLineText' } }
define root custom entity Y0000CO_C_SOILINE
{
      @UI.selectionField: [{ position: 10 }]
      @Consumption.filter: { mandatory: true, defaultValue: 'STD' }
  key SoiVersion  : y0000co_soivar;

      @UI.selectionField: [{ position: 20 }]
      @Consumption.filter.mandatory: true
  key FiscalYear  : gjahr;

      @UI.selectionField: [{ position: 30 }]
      @Consumption.filter.mandatory: true
  key CompanyCode : bukrs;

      @UI.selectionField: [{ position: 40 }]
      @Consumption.filter.defaultValue: '04'
  key ValueType   : wrttp;

      @UI.selectionField: [{ position: 50 }]
      @Consumption.filter.defaultValue: '000'
  key Version     : versn;

      @UI.lineItem: [{ position: 10 }]
      @UI.textArrangement: #TEXT_FIRST
      @ObjectModel.text.element: [ 'SoiLineText' ]
  key SoiLine     : y0000co_soiline;

      SoiLineText : abap.char(35);

      @UI.hidden: true
      Outline     : abap.numc(4);

      @UI.lineItem: [{ position: 20 }]
      @Semantics.amount.currencyCode: 'Currency'
      TotalAmount : abap.curr(15,2);

      Currency    : waers;
}
