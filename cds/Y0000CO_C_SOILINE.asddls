@EndUserText.label: 'SOI report - lines'
@ObjectModel.query.implementedBy: 'ABAP:Y0000CO_CL_SOI_QUERY'
@Metadata.allowExtensions: true
define root custom entity Y0000CO_C_SOILINE
{
      @Consumption.filter.mandatory: true
      @Consumption.defaultValue: 'STD'
  key SoiVersion  : y0000co_soivar;

      @Consumption.filter.mandatory: true
  key FiscalYear  : gjahr;

      @Consumption.filter.mandatory: true
  key CompanyCode : bukrs;

      @Consumption.defaultValue: '04'
  key ValueType   : wrttp;

      @Consumption.defaultValue: '000'
  key Version     : versn;

      @ObjectModel.text.element: [ 'SoiLineText' ]
  key SoiLine     : y0000co_soiline;

      SoiLineText : abap.char(35);
      Outline     : abap.numc(4);

      @Semantics.amount.currencyCode: 'Currency'
      TotalAmount : abap.curr(15,2);
      Currency    : waers;
}
