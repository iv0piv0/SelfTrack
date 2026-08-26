/**
 * @description       :
 * @author            : Lioz Elmalem
 * @group             :
 * @last modified on  : 04-22-2021
 * @last modified by  : Lioz Elmalem
 * Modifications Log
 * Ver   Date         Author         Modification
 * 1.0   04-22-2021   Lioz Elmalem   Initial Version
 * 2.0   07-14-2023   Ashley Keller  Add new fields to payload and assign endpoint based on SB or Production.
 **/
public with sharing class CreateExpressController {
  public Boolean isLightning { get; set; }
  public Boolean isSandbox { get; set; }
  public Boolean isProduction { get; set; }
  public Map<String, String> param;
  public String id { get; set; }
  public String error { get; set; }
  public boolean framed { get; set; }
  public reqData reqData { get; set; }
  public GW_Name__c retgateway { get; set; }
  public List<String> errors { get; set; }
  public GW_Name__c gateway { get; set; }
  public Case cas { get; set; }
  public Compliance__c profile { get; set; }
  private ExpressConfig__c config;
  public String endpoint {get; set;}
  private class MERAPIException extends Exception {
  }
  public CreateExpressController(ApexPages.StandardController stdController) {
    isLightning = [
      SELECT UserPreferencesLightningExperiencePreferred
      FROM User
      WHERE Id = :UserInfo.getUserId()
    ]
    .UserPreferencesLightningExperiencePreferred;
    config = [
      SELECT Exception_email__c, gateway_endpoint__c, sandbox_endpoint__c, secret__c
      FROM ExpressConfig__c
      LIMIT 1
    ];
    param = new Map<String, String>();
    try {
      param = ApexPages.currentPage().getParameters();
    } catch (Exception e) {
    }
    id = param.containsKey('id') ? param.get('id') : null;
    framed = param.containsKey('framed');
    isSandbox = ApexPages.currentPage()
      .getURL()
      .contains('CreateExpressSandbox');
    isProduction = ApexPages.currentPage()
      .getURL()
      .contains('CreateExpressProduction');
    if (id != null && id != '' && framed && !isSandbox && !isProduction) {
      gateway = getGW(id);
      if (gateway != null)
        reqData = new reqData(gateway);
    }

  }

    
  public CreateExpressController(String casid) {
    config = [
      SELECT Exception_email__c, gateway_endpoint__c, sandbox_endpoint__c, secret__c
      FROM ExpressConfig__c
      LIMIT 1
    ];
    id = casid;
  }
  public Pagereference CreateSandbox() {
    return Create4Case(false);
  }
  public Pagereference CreateProduction() {
    return Create4Case(true);
  }
  @future(callout=true)
  public static void create4Case(String casid, Boolean isProd) {
    CreateExpressController cec = new CreateExpressController(casid);
    cec.Create4Case(isProd);
  }
  public Pagereference Create4Case(Boolean isProd) {
    Pagereference pg = new Pagereference('/' + id);
    pg.setRedirect(true);
    cas = getCase(id);
    if (cas != null) {
      String url = '';
      if (cas.Company_Profile__c != null) {
        List<Website__c> webs = [
          SELECT Name
          FROM Website__c
          WHERE Compliance__c = :cas.Company_Profile__c
          LIMIT 1
        ];
        if (webs.size() > 0)
          url = webs[0].Name;
      }
      error = null;
      reqData = new reqData(cas, url, isProd);
      //Validations
      if (N(reqData.merchantEmail) == '')
        error = 'Merchant Email is Missing';
      else if (N(reqData.pppUsername) == '')
        error = 'Merchant Username is Missing';
      else if (N(reqData.pppPassword) == '')
        error = 'Merchant PPP Password is Missing';
      else if (N(reqData.descriptor) == '')
        error = 'Merchant Descriptor is Missing';
      else if (N(reqData.phoneNumber) == '')
        error = 'Merchant Phone is Missing';
      else if (N(reqData.country) == '')
        error = 'Merchant Country is Missing';
      else if (N(reqData.state) == '')
        error = 'Merchant State is Missing';
      else if (N(reqData.zip) == '')
        error = 'Merchant Zip is Missing';
      else if (N(reqData.city) == '')
        error = 'Merchant City is Missing';
      else if (N(reqData.street) == '')
        error = 'Merchant Street is Missing';
      else if (N(reqData.merchantUrl) == '')
        error = 'Merchant website url is Missing';
      if (error != null && !Test.isRunningTest())
        return null;
      Compliance__c profile = getProfile(cas.Company_Profile__c);
      List<String> errors = new List<String>();
      ExpressConfig__c config = [
        SELECT Exception_email__c, gateway_endpoint__c, sandbox_endpoint__c, secret__c
        FROM ExpressConfig__c
        LIMIT 1
      ];
      reqData.genCheckSum(config.secret__c);
      String data = reqData.genJSON();
      List<String> emailsTo = config.Exception_email__c.split(',');
      System.debug('gateway_endpoint: ' + endpoint);
      System.debug('Exception_email__c: ' + config.Exception_email__c);
      try {
        System.debug('accountType' + reqData.accountType);
        System.debug('data: ' + data);
          
        HttpRequest req = new HttpRequest();
       
       if (reqData.accountType == '1')
        {
           endpoint = config.gateway_endpoint__c;
        }
         else if (reqData.accountType == '2') 
         {
           endpoint = config.sandbox_endpoint__c;
         }
          
        req.setMethod('POST');
        req.setEndpoint(endpoint);
        req.setHeader('Content-Type', 'application/json; charset=utf-8');
        req.setHeader('Content-Length', '' + data.length());
        req.setTimeout(120000);
        req.setBody(data);
        String body = new Http().send(req).getBody();
        if (reqData != null) {
          if (reqData.accountType == '2') {
            cas.SB_GW_Login_ID__c = reqData.gatewayUsername;
            cas.SB_GW_Password__c = reqData.gatewayPassword;
            cas.SB_Client_ID__c = reqData.gatewayClientId;
            cas.SB_Client_Name__c = reqData.gatewayClientName;
            cas.SB_MultiClient_ID__c = reqData.gatewayMClientId;
            cas.SB_MultiClient_Name__c = reqData.gatewayMClientName;
          }
          cas.Create_Account_Response__c = body;
          update cas;
        }
        System.debug('response body: ' + body);
        if (body.replace(' ', '').contains('"status":"ERROR"'))
          throw new MERAPIException(data + '|-|-|' + body);
        Map<String,Object> resData = (Map<String,Object>) JSON.deserializeUntyped(body);
        if (resData != null) {
          Map<String,Object> createdAccountDetails;
          if(resData.containsKey('createdAccountDetails')) createdAccountDetails = (Map<String,Object>)resData.get('createdAccountDetails');
          else if(resData.containsKey('details')) createdAccountDetails = (Map<String,Object>)resData.get('details');
          
          if (reqData.accountType == '1') {
            GW_Name__c newgw = new GW_Name__c();
            newgw.Name = cas.Company_Profile__r.Name;
            newgw.Compliance__c = cas.Company_Profile__c;
            newgw.GW_Login_ID__c = (createdAccountDetails.containsKey('gatewayUsername') && createdAccountDetails.get('gatewayUsername')!=null) ? String.valueOf(createdAccountDetails.get('gatewayUsername')) : '';
            newgw.GW_Password__c = (createdAccountDetails.containsKey('gatewayPassword') && createdAccountDetails.get('gatewayPassword')!=null) ? String.valueOf(createdAccountDetails.get('gatewayPassword')) : '';
            newgw.Client_ID__c = (createdAccountDetails.containsKey('gatewayClientId') && createdAccountDetails.get('gatewayClientId')!=null) ? String.valueOf(createdAccountDetails.get('gatewayClientId')) : '';
            newgw.Client_Name__c = (createdAccountDetails.containsKey('gatewayClientName') && createdAccountDetails.get('gatewayClientName')!=null) ? String.valueOf(createdAccountDetails.get('gatewayClientName')) : '';
            newgw.MultiClient_ID__c = (createdAccountDetails.containsKey('gatewayMClientId') && createdAccountDetails.get('gatewayMClientId')!=null) ? String.valueOf(createdAccountDetails.get('gatewayMClientId')) : '';
            newgw.MultiClient_Name__c = (createdAccountDetails.containsKey('gatewayMClientName') && createdAccountDetails.get('gatewayMClientName')!=null) ? String.valueOf(createdAccountDetails.get('gatewayMClientName')) : '';
            newgw.Merchant_Site_ID__c = (createdAccountDetails.containsKey('merchantSiteId') && createdAccountDetails.get('merchantSiteId')!=null) ? String.valueOf(createdAccountDetails.get('merchantSiteId')) : '';
            newgw.Merchant_ID__c = (createdAccountDetails.containsKey('merchantId') && createdAccountDetails.get('merchantId')!=null) ? String.valueOf(createdAccountDetails.get('merchantId')) : '';
            newgw.CpanelUsername__c = reqData.pppUsername;
            newgw.CpanelPassword__c = reqData.pppPassword;
            newgw.SC_ACQ_MID__c = (createdAccountDetails.containsKey('mid') && createdAccountDetails.get('mid')!=null) ? String.valueOf(createdAccountDetails.get('mid')) : '';
              try{
                  insert newgw;
                  system.debug('new gw inserted');
              } 
              catch(exception e)
              { system.debug('insert gw failed');}
            cas.Activation_Link__c = (createdAccountDetails.containsKey('activationLink') && createdAccountDetails.get('activationLink')!=null) ? String.valueOf(createdAccountDetails.get('activationLink')) : '';
            cas.GW_Name__c = newgw.id;
            cas.Create_Account_Response__c = body;
            cas.SB_PPP_Password__c = reqData.pppPassword;
            cas.Merchant_ID__c = (createdAccountDetails.containsKey('merchantId') && createdAccountDetails.get('merchantId')!=null) ? String.valueOf(createdAccountDetails.get('merchantId')) : '';
            update cas;
          } else {
            cas.SB_Site_ID__c = (createdAccountDetails.containsKey('merchantSiteId') && createdAccountDetails.get('merchantSiteId')!=null) ? String.valueOf(createdAccountDetails.get('merchantSiteId')) : '';
            cas.Activation_Link__c = (createdAccountDetails.containsKey('activationLink') && createdAccountDetails.get('activationLink')!=null) ? String.valueOf(createdAccountDetails.get('activationLink')) : '';
            cas.SB_GW_Login_ID__c = (createdAccountDetails.containsKey('gatewayUsername') && createdAccountDetails.get('gatewayUsername')!=null) ? String.valueOf(createdAccountDetails.get('gatewayUsername')) : '';
            cas.SB_GW_Password__c = (createdAccountDetails.containsKey('gatewayPassword') && createdAccountDetails.get('gatewayPassword')!=null) ? String.valueOf(createdAccountDetails.get('gatewayPassword')) : '';
            cas.SB_Client_ID__c = (createdAccountDetails.containsKey('gatewayClientId') && createdAccountDetails.get('gatewayClientId')!=null) ? String.valueOf(createdAccountDetails.get('gatewayClientId')) : '';
            cas.SB_Client_Name__c = (createdAccountDetails.containsKey('gatewayClientName') && createdAccountDetails.get('gatewayClientName')!=null) ? String.valueOf(createdAccountDetails.get('gatewayClientName')) : '';
            cas.SB_MultiClient_ID__c = (createdAccountDetails.containsKey('gatewayMClientId') && createdAccountDetails.get('gatewayMClientId')!=null) ? String.valueOf(createdAccountDetails.get('gatewayMClientId')) : '';
            cas.SB_MultiClient_Name__c = (createdAccountDetails.containsKey('gatewayMClientName') && createdAccountDetails.get('gatewayMClientName')!=null) ? String.valueOf(createdAccountDetails.get('gatewayMClientName')) : '';
            cas.Merchant_Site_ID__c = (createdAccountDetails.containsKey('merchantSiteId') && createdAccountDetails.get('merchantSiteId')!=null) ? String.valueOf(createdAccountDetails.get('merchantSiteId')) : '';
            cas.SB_PPP_Username__c = reqData.pppUsername;
            cas.SB_PPP_Password__c = reqData.pppPassword;
            cas.Create_Account_Response__c = body;
            cas.Merchant_ID__c = (createdAccountDetails.containsKey('merchantId') && createdAccountDetails.get('merchantId')!=null) ? String.valueOf(createdAccountDetails.get('merchantId')) : '';
            update cas;
          }
        }
      } catch (Exception e) {
        try {
          if (reqData != null) {
            if (reqData.accountType == '2') {
              cas.SB_GW_Login_ID__c = reqData.gatewayUsername;
              cas.SB_GW_Password__c = reqData.gatewayPassword;
              cas.SB_Client_ID__c = reqData.gatewayClientId;
              cas.SB_Client_Name__c = reqData.gatewayClientName;
              cas.SB_MultiClient_ID__c = reqData.gatewayMClientId;
              cas.SB_MultiClient_Name__c = reqData.gatewayMClientName;
            }
            cas.SB_PPP_Password__c = reqData.pppPassword;
            update cas;
          }
        } catch (Exception e2) {
        }
        String typeName = e.getTypeName();
        String stackTrace = e.getStackTraceString();
        String message = e.getMessage();
        if (typeName.contains('.MERAPIException')) {
          error = 'MER API ERROR';
          List<String> dataNbody = message.split(Pattern.quote('|-|-|'));
          errors.add('request:');
          errors.add(dataNbody[0]);
          errors.add('-');
          errors.add('response:');
          errors.add(dataNbody[1]);
          profile.Configuration_Status__c = 'Issue';
          profile.Configuration_Issue_Details__c =
            error +
            '\n\n' +
            String.join(errors, '\n');
          update profile;
          emailAlert(profile, error, errors, emailsTo);
        }
        error = 'SALESFORCE ERROR';
        errors.add(typeName);
        errors.add(stackTrace);
        errors.add(message);
        profile.Configuration_Status__c = 'Issue';
        profile.Configuration_Issue_Details__c =
          error +
          '\n\n' +
          String.join(errors, '\n');
        update profile;
        emailAlert(profile, error, errors, emailsTo);
      }
    }
    return pg;
  }
  public static GW_Name__c getGW(String id) {
    List<GW_Name__c> gws = [
      SELECT
        id,
        Compliance__c,
        GW_Login_ID__c,
        GW_Password__c,
        Client_ID__c,
        Client_Name__c,
        MultiClient_ID__c,
        MultiClient_Name__c,
        Site_Name__c,
        Page_Title__c,
        Compliance__r.Descriptor__c,
        Compliance__r.City_Field__c,
        Compliance__r.Account__r.CS_Email__c,
        Compliance__r.Primary_Contact__r.FirstName,
        Compliance__r.Primary_Contact__r.LastName,
        Merchant_Site_ID__c,
        Merchant_ID__c,
        CpanelUsername__c,
        CpanelPassword__c,
        Compliance__r.MSA_Effective_Date__c,
        Compliance__r.Open_Date__c,
        Compliance__r.Origin_Region__c,
        Compliance__r.Overwrite_Financial_Vertical__c,
        Compliance__r.Name,
        Compliance__r.Sales_Rep__c,
        Compliance__r.Sales_Rep__r.Name,
        Compliance__r.Sales_Rep__r.Email,
        Compliance__r.Account_Manager__c,
        Compliance__r.Account_Manager__r.Name,
        Compliance__r.Account_Manager__r.Email,
        Compliance__r.Account_Operational_Manager_CP__c,
        Compliance__r.Account_Operational_Manager_CP__r.Name,
        Compliance__r.Account_Operational_Manager_CP__r.Email,
        Compliance__r.Account__c,
        Compliance__r.Account__r.Name,
        Compliance__r.From_Reseller__c,
        Compliance__r.From_Reseller__r.Name
        
      FROM GW_Name__c
      WHERE id = :id
    ];
    if (gws.size() > 0)
      return gws[0];
    else
      return null;
  }
  public static Case getCase(String id) {
    List<Case> cases = [
      SELECT
        id,
        Case_Ref_ID__c,
        Company_Profile__c,
        Company_Profile__r.Primary_Contact__r.FirstName,
        Company_Profile__r.Primary_Contact__r.LastName,
        Company_Profile__r.City_Field__c,
        Company_Profile__r.Account__r.CS_Email__c,
        Company_Profile__r.Descriptor__c,
        Company_Profile__r.MSA_Effective_Date__c,
        SB_Template__c,
        SB_Client_ID__c,
        SB_MultiClient_ID__c,
        SB_MultiClient_Name__c,
        SB_GW_Password__c,
        SB_GW_Login_ID__c,
        SB_Client_Name__c,
        SB_PPP_Username__c,
        SB_PPP_Password__c,
        Account.CreatedDate,
        Contact_Information__c,
        Company_Profile__r.Registered_Country_Code2__c,
        Company_Profile__r.Registered_State__c,
        Company_Profile__r.Registered_Zip_Postal_Code__c,
        Company_Profile__r.Registered_City__c,
        Company_Profile__r.Registered_Street__c,
        Company_Profile__r.MCC_Code__c,
        Client_s_Tier__c,
        Platform_Integration__c,
        Integration_Channel__c,
        
        Company_profile__r.Name,
        Company_Profile__r.Sales_Rep__c,
        Company_Profile__r.Sales_Rep__r.Name,
        Company_Profile__r.Sales_Rep__r.Email,
        Company_Profile__r.Account_Manager__c,
        Company_Profile__r.Account_Manager__r.Name,
        Company_Profile__r.Account_Manager__r.Email,
        Company_Profile__r.Account_Operational_Manager_CP__c,
        Company_Profile__r.Account_Operational_Manager_CP__r.Name,
        Company_Profile__r.Account_Operational_Manager_CP__r.Email,
        Company_Profile__r.Account__c,
        Company_Profile__r.Account__r.Name,
        Company_Profile__r.From_Reseller__c,
        Company_Profile__r.From_Reseller__r.Name,
        Company_Profile__r.From_Reseller__r.Overwrite_Financial_Vertical__c,
        Company_Profile__r.Overwrite_Financial_Vertical__c,
        Company_Profile__r.Origin_Region__c,
        Company_Profile__r.Open_Date__c,
        Company_Profile__r.From_Reseller__r.MCC_Code__c
      FROM Case
      WHERE id = :id
    ];
    if (cases.size() > 0)
      return cases[0];
    else
      return null;
  }

  private static void emailAlert(
    Compliance__c profile,
    String error,
    List<String> errors,
    List<String> emailsTo
  ) {
    Messaging.SingleEmailMessage alert = new Messaging.SingleEmailMessage();
    alert.setToAddresses(emailsTo); //<-- edit email list
    alert.setSenderDisplayName('CREATE_GATEWAY_API');
    alert.setSubject('API_Exception: ' + error);
    alert.setPlainTextBody(
      'Compliance__c: ' +
      JSON.serializePretty(profile) +
      '\n\n' +
      'Error: ' +
      error +
      '\n\n' +
      String.join(errors, '\n')
    );
    if(!Test.isRunningTest()) Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ alert });
  }
  public void sendVF() {
    if (reqData != null && gateway != null) {
      reqData.genCheckSum(config.secret__c);
      System.debug('***** request data(reqData):' + reqData);
      List<Object> objs = getData(
        reqData.genJSON(),
        gateway.id,
        gateway.Compliance__c
      );
      profile = (Compliance__c) objs[0];
      error = (String) objs[1];
      errors = (List<String>) objs[2];
      retgateway = (GW_Name__c) objs[3];
      gateway = retgateway;
    }
  }
  public static Map<String, Map<string, String>> pTemplates = new Map<String, Map<string, String>>{
    'PlayTech' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '4936',
      'configClientId' => '4937',
      'defaultMerchantSiteId' => '188928',
      'accountIndustryType' => '2',
      'gwTransType' => 'Sale'
    },
    'SbTech' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '4952',
      'configClientId' => '4955',
      'defaultMerchantSiteId' => '188978',
      'accountIndustryType' => '1',
      'gwTransType' => 'Sale'
    },
    'General' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '4965',
      'configClientId' => '4967',
      'defaultMerchantSiteId' => '189038',
      'accountIndustryType' => '1',
      'gwTransType' => 'Sale'
    },
    'Gaming' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '4940',
      'configClientId' => '4941',
      'defaultMerchantSiteId' => '188938',
      'accountIndustryType' => '1',
      'gwTransType' => 'Sale'
    },
    'Travel' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '4956',
      'configClientId' => '4957',
      'defaultMerchantSiteId' => '188988',
      'accountIndustryType' => '2',
      'gwTransType' => 'Auth'
    },
    'Forex' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '4946',
      'configClientId' => '4947',
      'defaultMerchantSiteId' => '188948',
      'accountIndustryType' => '1',
      'gwTransType' => 'Sale'
    },
      'ECommerce Blank Bank template' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '4948',
      'configClientId' => '151002881',
      'defaultMerchantSiteId' => '188968',
      'accountIndustryType' => '2',
      'gwTransType' => 'Sale'
    },
      'Retail Blank Bank template' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '4964',
      'configClientId' => '151004332',
      'defaultMerchantSiteId' => '189028',
      'accountIndustryType' => '2',
      'gwTransType' => 'Auth'
    },
      'Gaming Blank Bank template' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '4940',
      'configClientId' => '151004331',
      'defaultMerchantSiteId' => '188938',
      'accountIndustryType' => '1',
      'gwTransType' => 'Sale'
    },
    'Ecommerce' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '4948',
      'configClientId' => '4949',
      'defaultMerchantSiteId' => '188968',
      'accountIndustryType' => '2',
      'gwTransType' => 'Sale'
    },
    'Retail' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '4964',
      'configClientId' => '4966',
      'defaultMerchantSiteId' => '189028',
      'accountIndustryType' => '2',
      'gwTransType' => 'Auth'
    }
  };
  public static Map<String, Map<string, String>> sbTemplates = new Map<String, Map<string, String>>{
    'PlayTech' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '24637',
      'configClientId' => '24611',
      'defaultMerchantSiteId' => '192476',
      'accountIndustryType' => '2',
      'gwTransType' => 'Sale'
    },
    'SbTech' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '24637',
      'configClientId' => '24618',
      'defaultMerchantSiteId' => '192478',
      'accountIndustryType' => '1',
      'gwTransType' => 'Sale'
    },
    'General' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '24637',
      'configClientId' => '24619',
      'defaultMerchantSiteId' => '192486',
      'accountIndustryType' => '1',
      'gwTransType' => 'Sale'
    },
    'Gaming' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '24637',
      'configClientId' => '24620',
      'defaultMerchantSiteId' => '192488',
      'accountIndustryType' => '1',
      'gwTransType' => 'Sale'
    },
    'Travel' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '24637',
      'configClientId' => '24621',
      'defaultMerchantSiteId' => '192498',
      'accountIndustryType' => '2',
      'gwTransType' => 'Auth'
    },
    'Forex' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '24637',
      'configClientId' => '24622',
      'defaultMerchantSiteId' => '192506',
      'accountIndustryType' => '1',
      'gwTransType' => 'Sale'
    },
      'ECommerce Blank Bank template' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '24637',
      'configClientId' => '24623',
      'defaultMerchantSiteId' => '192518',
      'accountIndustryType' => '2',
      'gwTransType' => 'Sale'
    },
      'Retail Blank Bank template' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '24637',
      'configClientId' => '24626',
      'defaultMerchantSiteId' => '192528',
      'accountIndustryType' => '2',
      'gwTransType' => 'Auth'
    },
      'Gaming Blank Bank template' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '24637',
      'configClientId' => '24620',
      'defaultMerchantSiteId' => '192488',
      'accountIndustryType' => '1',
      'gwTransType' => 'Sale'
    },
    'Ecommerce' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '24637',
      'configClientId' => '24623',
      'defaultMerchantSiteId' => '192518',
      'accountIndustryType' => '2',
      'gwTransType' => 'Sale'
    },
    'Retail' => new Map<String, String>{
      'domainType' => '1',
      'configMultiClientId' => '24637',
      'configClientId' => '24626',
      'defaultMerchantSiteId' => '192528',
      'accountIndustryType' => '2',
      'gwTransType' => 'Auth'
    }
  };
  public class reqData {
    public String isExpress { get; set; }
    public String merchantName { get; set; }
    public String merchantEmail { get; set; }
    public String pppUsername { get; set; }
    public String pppPassword { get; set; }
    public String domainType { get; set; }
    public String merchantStatus { get; set; }
    public String defaultLanguage { get; set; }
    public String gatewayUsername { get; set; }
    public String gatewayPassword { get; set; }
    public String gatewayClientId { get; set; }
    public String gatewayClientName { get; set; }
    public String gatewayMClientId { get; set; }
    public String gatewayMClientName { get; set; }
    public String userRoleName { get; set; }
    public String siteName { get; set; }
    public String descriptor { get; set; }
    public String phoneNumber { get; set; }
    public String pageTitle { get; set; }
    public String managingCompanyNumber { get; set; }
    public String pppUserFirstName { get; set; }
    public String pppUserLastName { get; set; }
    public String defaultMerchantSiteId { get; set; }
    public String accountIndustryType { get; set; }
    public String gwTransType { get; set; }
    public String accountType { get; set; }
    public String mode3d { get; set; }
    public String adminAmongMerchantLogins { get; set; }
    public String timestamp { get; set; }
    public String checksum { get; set; }
    public String configMultiClientId { get; set; }
    public String configClientId { get; set; }
    public String dateSigned { get; set; }
    public String sfId { get; set; }
    public String integrationCaseId { get; set; }
    public String country { get; set; }
    public String state { get; set; }
    public String zip { get; set; }
    public String city { get; set; }
    public String street { get; set; }
    public String mccCode { get; set; }
    public String phone { get; set; }
    public String merchantUrl { get; set; }
    public String customerIntegrationChannel { get; set; }
    public String platform { get; set; }
    public String customerTier { get; set; }
    public String salesRepId { get; set; }
    public String salesRepName { get; set; }
    public String salesRepEmail { get; set; }
    public String accountManagerId { get; set; }
    public String accountManagerName { get; set; }
    public String accountManagerEmail { get; set; }
    public String operationalManagerId { get; set; }
    public String operationalManagerName { get; set; }
    public String operationalManagerEmail { get; set; }
    public String companyId { get; set; }
    public String companyName { get; set; }
    public String accountId { get; set; }
    public String accountName { get; set; }
    public String introducerId { get; set; }
    public String introducerName { get; set; }
    public String introducerIndustry {get; set;}
    public String mcc {get; set;}
    public String activationDate {get;set;}
    public String businessOriginId {get; set;}
    public String businessOriginName {get; set;}
    public String industryName {get; set;}
    public String industryId {get; set;}

    public reqData(GW_Name__c gw) {
      isExpress = '';
      merchantName = gw.MultiClient_Name__c;
      merchantEmail = gw.Compliance__r.Account__r.CS_Email__c;
      pppUsername = gw.CpanelUsername__c != null
        ? gw.CpanelUsername__c
        : gw.Compliance__r.Account__r.CS_Email__c;
      pppPassword = gw.CpanelPassword__c != null ? gw.CpanelPassword__c : '';
      domainType = '1';
      merchantStatus = '3';
      defaultLanguage = 'en_US';
      gatewayUsername = gw.GW_Login_ID__c;
      gatewayPassword = gw.GW_Password__c;
      gatewayClientId = gw.Client_ID__c;
      gatewayClientName = gw.Client_Name__c;
      gatewayMClientId = gw.MultiClient_ID__c;
      gatewayMClientName = gw.MultiClient_Name__c;
      userRoleName = 'tempUser';
      siteName = gw.Site_Name__c;
      descriptor = gw.Compliance__r.Descriptor__c;
      phoneNumber = gw.Compliance__r.City_Field__c;
      pageTitle = gw.Page_Title__c;
      managingCompanyNumber = '1';
      pppUserFirstName = gw.Compliance__r.Primary_Contact__r.FirstName;
      pppUserLastName = gw.Compliance__r.Primary_Contact__r.LastName;
      defaultMerchantSiteId = '';
      accountIndustryType = '1';
      gwTransType = '';
      accountType = '1';
      mode3d = '1';
      adminAmongMerchantLogins = '1';
      Datetime dat = gw.Compliance__r.MSA_Effective_Date__c;
      dateSigned = dat != null
        ? dat.formatGMT('yyyy-MM-dd HH:mm:ss.SSS')
        : null;
      sfid = gw.Compliance__c;
      salesRepId = gw.Compliance__r.Sales_Rep__c;
      salesRepName = gw.Compliance__r.Sales_Rep__r.Name;
      salesRepEmail = gw.Compliance__r.Sales_Rep__r.Email;
      accountManagerId = gw.Compliance__r.Account_Manager__c;
      accountManagerName = gw.Compliance__r.Account_Manager__r.Name;
      accountManagerEmail = gw.Compliance__r.Account_Manager__r.Email;
      operationalManagerId = gw.Compliance__r.Account_Operational_Manager_CP__c;
      operationalManagerName = gw.Compliance__r.Account_Operational_Manager_CP__r.Name;
      operationalManagerEmail = gw.Compliance__r.Account_Operational_Manager_CP__r.Email;
      companyId = gw.Compliance__c;
      companyName = gw.Compliance__r.Name;
      accountId = gw.Compliance__r.Account__c;
      accountName = gw.Compliance__r.Account__r.Name;
      introducerId = gw.Compliance__r.From_Reseller__c;
      introducerName = gw.Compliance__r.From_Reseller__r.Name;
      switch on (gw.Compliance__r.From_Reseller__r.Overwrite_Financial_Vertical__c)
        {
              when 'Cryptocurrency' {introducerIndustry = '1';}
              when 'Marketplace' {introducerIndustry = '2';}
              when 'Social Gaming' {introducerIndustry = '3';}
          }
      mcc = gw.Compliance__r.From_Reseller__r.MCC_Code__c;
      Datetime dat2 = gw.Compliance__r.Open_Date__c;
      activationDate = dat2 != null
        ? dat2.formatGMT('yyyy-MM-dd HH:mm:ss.SSS')
        : null;
      businessOriginName =  gw.Compliance__r.Origin_Region__c;
      switch on (gw.Compliance__r.Origin_Region__c)
        {
              when 'NA' {businessOriginId = '1';}
              when 'EMEA' {businessOriginId = '2';}
              when 'LATAM' {businessOriginId = '3';}
              when 'APAC' {businessOriginId = '4';}
          }
        
      industryName = gw.Compliance__r.Overwrite_Financial_Vertical__c;
      switch on (gw.Compliance__r.Overwrite_Financial_Vertical__c)
        {
              when 'Cryptocurrency' {industryId = '1';}
              when 'Marketplace' {industryId = '2';}
              when 'Social Gaming' {industryId = '3';}

         }
    }
      
    public String genPassword(Integer len) {
      final String upchars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      final String lowchars = 'abcdefghijklmnopqrstuvwxyz';
      final String numchars = '0123456789';
      String randStr = '';
      Integer idx = Math.mod(
        Math.abs(Crypto.getRandomInteger()),
        upchars.length()
      );
      randStr += upchars.substring(idx, idx + 1);
      idx = Math.mod(Math.abs(Crypto.getRandomInteger()), lowchars.length());
      randStr += lowchars.substring(idx, idx + 1);
      idx = Math.mod(Math.abs(Crypto.getRandomInteger()), numchars.length());
      randStr += numchars.substring(idx, idx + 1);
      while (randStr.length() < len) {
        idx = Math.mod(
          Math.abs(Crypto.getRandomInteger()),
          (upchars + lowchars + numchars).length()
        );
        randStr += (upchars + lowchars + numchars).substring(idx, idx + 1);
      }
      return randStr;
    }
    public reqData(Case cas, String url, Boolean isProd) {
      isExpress = '0';
      merchantName = cas.Company_Profile__r.Name;
      merchantEmail = cas.Contact_Information__c;

      country = cas.Company_Profile__r.Registered_Country_Code2__c;
      state = cas.Company_Profile__r.Registered_State__c;
      zip = cas.Company_Profile__r.Registered_Zip_Postal_Code__c;
      city = cas.Company_Profile__r.Registered_City__c;
      street = cas.Company_Profile__r.Registered_Street__c;
      if (street != null)
        street = street.left(30);
      phone = cas.Company_Profile__r.City_Field__c;
      merchantUrl = url;
      descriptor = cas.Company_Profile__r.Descriptor__c;
      phoneNumber = cas.Company_Profile__r.City_Field__c;
      if (!isProd) {
        /*if(N(country)=='')      */ country = 'GBR';
        /*if(N(state)=='')        */ state = 'test';
        /*if(N(zip)=='')          */ zip = '123456';
        /*if(N(city)=='')         */ city = 'test';
        /*if(N(street)=='')       */ street = 'test';
        /*if(N(phone)=='')        */ phone = '123456';
        /*if(N(merchantUrl)=='')  */ merchantUrl = 'www.test.com';
        /*if(N(descriptor)=='')   */ descriptor = 'test';
        /*if(N(phoneNumber)=='')  */ phoneNumber = 'test';
      }
      mccCode = cas.Company_Profile__r.MCC_Code__c;
      customerIntegrationChannel = cas.Integration_Channel__c;
      platform = cas.Platform_Integration__c;
      customerTier = cas.Client_s_Tier__c;
      siteName = cas.Company_Profile__r.Name;
      pageTitle = cas.Company_Profile__r.Name;
      pppUsername = cas.SB_PPP_Username__c != null
        ? cas.SB_PPP_Username__c
        : '';
      pppPassword = cas.SB_PPP_Password__c != null
        ? cas.SB_PPP_Password__c
        : genPassword(8);
      merchantStatus = '3';
      defaultLanguage = 'en_US';
      gatewayUsername = cas.SB_GW_Login_ID__c;
      gatewayPassword = cas.SB_GW_Password__c;
      gatewayClientId = cas.SB_Client_ID__c;
      gatewayClientName = cas.SB_Client_Name__c;
      gatewayMClientId = cas.SB_MultiClient_ID__c;
      gatewayMClientName = cas.SB_MultiClient_Name__c;
      managingCompanyNumber = '1';
      pppUserFirstName = cas.Company_Profile__r.Primary_Contact__r.FirstName;
      pppUserLastName = cas.Company_Profile__r.Primary_Contact__r.LastName;
      accountType = isProd == true ? '1' : '2';
      userRoleName = accountType == '1' ? 'tempUser' : 'management';
      mode3d = '1';
      adminAmongMerchantLogins = '1';
      Map<String, Map<string, String>> curTemplate = isProd
        ? CreateExpressController.pTemplates
        : CreateExpressController.sbTemplates;
      if (curTemplate.containsKey(cas.SB_Template__c)) {
        domainType = (String) curTemplate.get(cas.SB_Template__c)
          .get('domainType');
        configMultiClientId = (String) curTemplate.get(cas.SB_Template__c)
          .get('configMultiClientId');
        defaultMerchantSiteId = (String) curTemplate.get(cas.SB_Template__c)
          .get('defaultMerchantSiteId');
        configClientId = (String) curTemplate.get(cas.SB_Template__c)
          .get('configClientId');
        accountIndustryType = (String) curTemplate.get(cas.SB_Template__c)
          .get('accountIndustryType');
        gwTransType = (String) curTemplate.get(cas.SB_Template__c)
          .get('gwTransType');
      }
      Datetime dat = cas.Company_Profile__r.MSA_Effective_Date__c;
      dateSigned = dat != null
        ? dat.formatGMT('yyyy-MM-dd HH:mm:ss.SSS')
        : null;
      sfid = cas.Company_Profile__c;
      integrationCaseId = cas.Case_Ref_ID__c;

      salesRepId = cas.Company_Profile__r.Sales_Rep__c;
      salesRepName = cas.Company_Profile__r.Sales_Rep__r.Name;
      salesRepEmail = cas.Company_Profile__r.Sales_Rep__r.Email;
      accountManagerId = cas.Company_Profile__r.Account_Manager__c;
      accountManagerName = cas.Company_Profile__r.Account_Manager__r.Name;
      accountManagerEmail = cas.Company_Profile__r.Account_Manager__r.Email;
      operationalManagerId = cas.Company_Profile__r.Account_Operational_Manager_CP__c;
      operationalManagerName = cas.Company_Profile__r.Account_Operational_Manager_CP__r.Name;
      operationalManagerEmail = cas.Company_Profile__r.Account_Operational_Manager_CP__r.Email;
      companyId = cas.Company_Profile__c;
      companyName = cas.Company_Profile__r.Name;
      accountId = cas.Company_Profile__r.Account__c;
      accountName = cas.Company_Profile__r.Account__r.Name;
      introducerId = cas.Company_Profile__r.From_Reseller__c;
      introducerName = cas.Company_Profile__r.From_Reseller__r.Name;
          switch on (cas.Company_Profile__r.From_Reseller__r.Overwrite_Financial_Vertical__c)
            {
                  when 'Cryptocurrency' {introducerIndustry = '1';}
                  when 'Marketplace' {introducerIndustry = '2';}
                  when 'Social Gaming' {introducerIndustry = '3';}
             }
      mcc = cas.Company_profile__r.From_Reseller__r.MCC_Code__c;
      Datetime dat2 = cas.Company_profile__r.Open_Date__c;
      activationDate = dat2 != null
        ? dat2.formatGMT('yyyy-MM-dd HH:mm:ss.SSS')
        : null;
      businessOriginName =  cas.Company_Profile__r.Origin_Region__c;
      switch on (cas.Company_profile__r.Origin_Region__c)
        {
              when 'NA' {businessOriginId = '1';}
              when 'EMEA' {businessOriginId = '2';}
              when 'LATAM' {businessOriginId = '3';}
              when 'APAC' {businessOriginId = '4';}
          }
        
      industryName = cas.Company_profile__r.Overwrite_Financial_Vertical__c;
      switch on (cas.Company_profile__r.Overwrite_Financial_Vertical__c)
        {
              when 'Cryptocurrency' {industryId = '1';}
              when 'Marketplace' {industryId = '2';}
              when 'Social Gaming' {industryId = '3';}
         }
    
      
    }
    public void genCheckSum(String secret) {
      timestamp = System.now().format('yyyy-MM-dd HH:mm:ss');
      checksum = EncodingUtil.convertToHex(
        Crypto.generateDigest(
          'SHA-256',
          Blob.valueOf(
            N(isExpress) +
            N(merchantName) +
            N(merchantEmail) +
            N(pppUsername) +
            N(pppPassword) +
            N(domainType) +
            N(merchantStatus) +
            N(defaultLanguage) +
            N(gatewayUsername) +
            N(gatewayPassword) +
            N(gatewayClientId) +
            N(gatewayClientName) +
            N(gatewayMClientId) +
            N(gatewayMClientName) +
            N(userRoleName) +
            N(siteName) +
            N(descriptor) +
            N(phoneNumber) +
            N(pageTitle) +
            N(managingCompanyNumber) +
            N(pppUserFirstName) +
            N(pppUserLastName) +
            N(defaultMerchantSiteId) +
            N(accountIndustryType) +
            N(gwTransType) +
            N(accountType) +
            N(mode3d) +
            N(adminAmongMerchantLogins) +
            N(configMultiClientId) +
            N(configClientId) +
            N(dateSigned) +
            N(sfid) +
            N(integrationCaseId) +
            N(country) +
            N(state) +
            N(zip) +
            N(city) +
            N(street) +
            N(mccCode) +
            N(phone) +
            N(merchantUrl) +
            N(customerIntegrationChannel) +
            N(platform) +
            N(customerTier) +
            N(timestamp) +
            N(secret)
          )
        )
      );
      System.debug(checksum);
    }
    public String genJSON() {
      JSONGenerator gen = JSON.createGenerator(true);
      gen.writeStartObject();
      gen.writeStringField('isExpress', N(isExpress));
      gen.writeStringField('merchantName', N(merchantName));
      gen.writeStringField('merchantEmail', N(merchantEmail));
      gen.writeStringField('pppUsername', N(pppUsername));
      gen.writeStringField('pppPassword', N(pppPassword));
      gen.writeStringField('domainType', N(domainType));
      gen.writeStringField('merchantStatus', N(merchantStatus));
      gen.writeStringField('defaultLanguage', N(defaultLanguage));
      gen.writeStringField('gatewayUsername', N(gatewayUsername));
      gen.writeStringField('gatewayPassword', N(gatewayPassword));
      if (N(gatewayClientId) != '')
        gen.writeStringField('gatewayClientId', N(gatewayClientId));
      gen.writeStringField('gatewayClientName', N(gatewayClientName));
      if (N(gatewayMClientId) != '')
        gen.writeStringField('gatewayMClientId', N(gatewayMClientId));
      gen.writeStringField('gatewayMClientName', N(gatewayMClientName));
      gen.writeStringField('userRoleName', N(userRoleName));
      gen.writeStringField('siteName', N(siteName));
      gen.writeStringField('descriptor', N(descriptor));
      gen.writeStringField('phoneNumber', N(phoneNumber));
      gen.writeStringField('pageTitle', N(pageTitle));
      gen.writeStringField('managingCompanyNumber', N(managingCompanyNumber));
      gen.writeStringField('pppUserFirstName', N(pppUserFirstName));
      gen.writeStringField('pppUserLastName', N(pppUserLastName));
      gen.writeStringField('defaultMerchantSiteId', N(defaultMerchantSiteId));
      gen.writeStringField('accountIndustryType', N(accountIndustryType));
      gen.writeStringField('gwTransType', N(gwTransType));
      gen.writeStringField('accountType', N(accountType));
      gen.writeStringField('mode3d', N(mode3d));
      gen.writeStringField(
        'adminAmongMerchantLogins',
        N(adminAmongMerchantLogins)
      );
      gen.writeStringField('configMultiClientId', N(configMultiClientId));
      gen.writeStringField('configClientId', N(configClientId));
      gen.writeStringField('dateSigned', N(dateSigned));
      gen.writeStringField('sfid', N(sfid));
      gen.writeStringField('integrationCaseId', N(integrationCaseId));
      gen.writeStringField('country', N(country));
      gen.writeStringField('state', N(state));
      gen.writeStringField('zip', N(zip));
      gen.writeStringField('city', N(city));
      gen.writeStringField('street', N(street));
      gen.writeStringField('mccCode', N(mccCode));
      gen.writeStringField('phone', N(phone));
      gen.writeStringField('merchantUrl', N(merchantUrl));
      gen.writeStringField(
        'customerIntegrationChannel',
        N(customerIntegrationChannel)
      );
      gen.writeStringField('platform', N(platform));
      gen.writeStringField('customerTier', N(customerTier));
      gen.writeStringField('timestamp', N(timestamp));
      gen.writeStringField('checksum', N(checksum));

      gen.writeObjectField('clientManagementDetailsInfo', new Map<String,Object>{
        'salesrep' => new Map<String,String>{
          'id' => salesRepId,
          'name' => salesRepName,
          'email' => salesRepEmail
        },
        'accountManager' => new Map<String,String>{
          'id' => accountManagerId,
          'name' => accountManagerName,
          'email' => accountManagerEmail
        },
        'operationalManager' => new Map<String,String>{
          'id' => operationalManagerId,
          'name' => operationalManagerName,
          'email' => operationalManagerEmail
        },
        'company' => new Map<String,String>{
          'id' => companyId,
          'name' => companyName
        },
        'account' => new Map<String,String>{
          'id' => accountId,
          'name' => accountName
        },
        'introducer' => new Map<String,String>{
          'id' => introducerId,
          'name' => introducerName,
          'industryIndicationId' => introducerIndustry,
          'mcc' => mcc
        },      
         'businessOriginRegion' => new Map<String,String>{
         'id' => businessOriginId,
         'name' => businessOriginName
        },      
         'industryIndication' => new Map<String,String>{
         'id' => industryId,
         'name' => industryName
        }
      });
      gen.writeStringField('activationDate',N(activationDate));

      gen.writeEndObject();
      return gen.getAsString();
    }
    public String N(String s) {
      return s != null ? s : '';
    }
  }
  public class resData {
    public createdAcc createdAccountDetails;
  }
  public class createdAcc {
    public String gatewayUsername;
    public String gatewayPassword;
    public String gatewayClientId;
    public String gatewayClientName;
    public String gatewayMClientId;
    public String gatewayMClientName;
    public String pppUsername;
    public String merchantSiteId;
    public String merchantId;
    public String activationLink;
    public String mid;
  }
  public with sharing class Param {
    @InvocableVariable(label='id' required=true)
    public String id;
    @InvocableVariable(label='password' required=true)
    public String password;
  }
  public static String N(String s) {
    return s != null ? s : '';
  }
  @InvocableMethod(label='imExpress')
  public static void imExpress(Param[] params) {
    Param param = params[0];
    System.debug('***** imExpress ivocable');
    reqData reqData;
    if (param.id != null && param.id != '') {
      GW_Name__c gateway = getGW(param.id);
      if (gateway != null) {
        reqData = new reqData(gateway);
        reqData.pppPassword = param.password;
        ExpressConfig__c config = [
          SELECT Exception_email__c, gateway_endpoint__c, sandbox_endpoint__c, secret__c
          FROM ExpressConfig__c
          LIMIT 1
        ];
        reqData.genCheckSum(config.secret__c);
        futureExpress(reqData.genJSON(), gateway.id, gateway.Compliance__c);
      }
    }
    System.debug('***** imExpress ENDED');
  }
  @future(callout=true)
  public static void futureExpress(String reqData, String gwid, String profid) {
    System.debug('***** futureExpress future');
    getData(reqData, gwid, profid);
  }
  public static List<Object> getData(String data, String gwid, String profid) {
    reqData reqData = (reqData) JSON.deserialize(data, reqData.class);
    Compliance__c profile = getProfile(profid);
    String error = null;
    List<String> errors = new List<String>();
    GW_Name__c gw = getGW(gwid);
    ExpressConfig__c config = [
      SELECT Exception_email__c, gateway_endpoint__c, sandbox_endpoint__c, secret__c
      FROM ExpressConfig__c
      LIMIT 1
    ];
    List<String> emailsTo = config.Exception_email__c.split(',');
    string endpoint; 
    system.debug('endpoint' + endpoint);
    System.debug('Exception_email__c: ' + config.Exception_email__c);
    try {
      System.debug('data: ' + data);
      HttpRequest req = new HttpRequest();
        if (reqData.accountType == '1')
        {
           endpoint = config.gateway_endpoint__c;
        }
         else if (reqData.accountType == '2') 
         {
           endpoint = config.sandbox_endpoint__c;
         }
      req.setEndpoint(endpoint);
      req.setHeader('Content-Type', 'application/json; charset=utf-8');
      req.setHeader('Content-Length', '' + data.length());
      req.setTimeout(120000);
      req.setBody(data);
      String body = new Http().send(req).getBody();
      if (reqData != null) {
        gw.GW_Login_ID__c = reqData.gatewayUsername;
        gw.GW_Password__c = reqData.gatewayPassword;
        gw.Client_ID__c = reqData.gatewayClientId;
        gw.Client_Name__c = reqData.gatewayClientName;
        gw.MultiClient_ID__c = reqData.gatewayMClientId;
        gw.MultiClient_Name__c = reqData.gatewayMClientName;
        gw.Site_Name__c = reqData.siteName;
        gw.Page_Title__c = reqData.pageTitle;
        update gw;
      }
      System.debug('response body: ' + body);
      if (body.replace(' ', '').contains('"status":"ERROR"'))
        throw new MERAPIException(data + '|-|-|' + body);
      Map<String,Object> resData = (Map<String,Object>) JSON.deserializeUntyped(body);
      if (resData != null) {
        Map<String,Object> createdAccountDetails;
        if(resData.containsKey('createdAccountDetails')) createdAccountDetails = (Map<String,Object>)resData.get('createdAccountDetails');
        else if(resData.containsKey('details')) createdAccountDetails = (Map<String,Object>)resData.get('details');
        gw.GW_Login_ID__c = createdAccountDetails.containsKey('gatewayUsername') ? (String)createdAccountDetails.get('gatewayUsername') : '';
        gw.GW_Password__c = createdAccountDetails.containsKey('gatewayPassword') ? (String)createdAccountDetails.get('gatewayPassword') : '';
        gw.Client_ID__c = createdAccountDetails.containsKey('gatewayClientId') ? (String)createdAccountDetails.get('gatewayClientId') : '';
        gw.Client_Name__c = createdAccountDetails.containsKey('gatewayClientName') ? (String)createdAccountDetails.get('gatewayClientName') : '';
        gw.MultiClient_ID__c = createdAccountDetails.containsKey('gatewayMClientId') ? (String)createdAccountDetails.get('gatewayMClientId') : '';
        gw.MultiClient_Name__c = createdAccountDetails.containsKey('gatewayMClientName') ? (String)createdAccountDetails.get('gatewayMClientName') : '';
        gw.Merchant_Site_ID__c = createdAccountDetails.containsKey('merchantSiteId') ? (String)createdAccountDetails.get('merchantSiteId') : '';
        gw.Merchant_ID__c = createdAccountDetails.containsKey('merchantId') ? (String)createdAccountDetails.get('merchantId') : '';
        gw.CpanelUsername__c = reqData.pppUsername;
        gw.CpanelPassword__c = reqData.pppPassword;
        gw.SC_ACQ_MID__c = createdAccountDetails.containsKey('mid') ? (String)createdAccountDetails.get('mid') : '';
        update gw;
      }
    } catch (Exception e) {
      try {
        if (reqData != null) {
          gw.GW_Login_ID__c = reqData.gatewayUsername;
          gw.GW_Password__c = reqData.gatewayPassword;
          gw.Client_ID__c = reqData.gatewayClientId;
          gw.Client_Name__c = reqData.gatewayClientName;
          gw.MultiClient_ID__c = reqData.gatewayMClientId;
          gw.MultiClient_Name__c = reqData.gatewayMClientName;
          gw.Site_Name__c = reqData.siteName;
          gw.Page_Title__c = reqData.pageTitle;
          update gw;
        }
      } catch (Exception e2) {
      }
      String typeName = e.getTypeName();
      String stackTrace = e.getStackTraceString();
      String message = e.getMessage();
      if (typeName.contains('.MERAPIException')) {
        error = 'MER API ERROR';
        List<String> dataNbody = message.split(Pattern.quote('|-|-|'));
        errors.add('request:');
        errors.add(dataNbody[0]);
        errors.add('-');
        errors.add('response:');
        errors.add(dataNbody[1]);
        profile.Configuration_Status__c = 'Issue';
        profile.Configuration_Issue_Details__c =
          error +
          '\n\n' +
          String.join(errors, '\n');
        update profile;
        emailAlert(profile, error, errors, emailsTo);
        return new List<Object>{ profile, error, errors, gw };
      }
      error = 'SALESFORCE ERROR';
      errors.add(typeName);
      errors.add(stackTrace);
      errors.add(message);
      profile.Configuration_Status__c = 'Issue';
      profile.Configuration_Issue_Details__c =
        error +
        '\n\n' +
        String.join(errors, '\n');
      update profile;
      emailAlert(profile, error, errors, emailsTo);
    }
    return new List<Object>{ profile, error, errors, gw };
  }
  private static Compliance__c getProfile(String id) {
    return [
      SELECT
        Is_Marketplace__c,
        Company_Type__c,
        Id,
        Name, //multiclientName, clientName, shopID, companyName
        MCC_Code__c, //MCCCode
        Registered_Street__c, //address1
        Registered_City__c, //city
        //?                            //state
        Registered_Zip_Postal_Code__c, //zip
        Registered_Country__c, //country
        Registered_Country_Code2__c, //country
        Registered_State__c,
        Descriptor__c, //merchantName
        City_field__c, //merchantPhone
        Primary_Contact__c, //contact
        Primary_Contact__r.Email, //email
        Primary_Contact__r.Phone, //phone
        Primary_Contact__r.MailingStreet, //address1
        Primary_Contact__r.MailingCity, //city
        Primary_Contact__r.MailingState, //state
        Primary_Contact__r.MailingPostalCode, //zip
        Primary_Contact__r.MailingCountry, //country
        Primary_Contact__r.MailingCountryCode__c
      FROM Compliance__c
      WHERE Id = :id
    ];
  }
}
