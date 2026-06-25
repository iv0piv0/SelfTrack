/**
 * @ Author: ITmyWay - ZedXagE
 * @ Create Time: 2020-05-17 12:21:08
 * @ Modified by: ZedXagE
 * @ Modified time: 2020-05-17 12:40:54
 * @ Description:
 */

@RestResource(urlMapping='/certificate')
global class CertificateController {
    global class CRTrequest{
        global String merchantId;
        global String certificationType;
        global Boolean certificationComplete;
    }
  global class CRTresponse{
        global String status;
        global Integer errorCode;
        global String errorMessage;
    }
    @HttpPost
    global static CRTresponse checkCert() {
    CRTresponse resp = new CRTresponse();
    resp.status = 'failure';
    try{
            String reqBody = RestContext.request.requestBody.toString();
      CRTrequest req = (CRTrequest)JSON.deserialize(reqBody, CRTrequest.class);
      if(req.merchantId!=null){
                List <Case> cases = [select id, Certification_Log__c from Case where Merchant_ID__c=:req.merchantId limit 1];
        if(cases.size()>0){
                    cases[0].Certification_Log__c = reqBody;
                    if(req.certificationType=='integration'&&req.certificationComplete==true)   cases[0].Acceptance_test__c = true;
                    else if(req.certificationType=='production'&&req.certificationComplete==true)   cases[0].Certification_Prod__c = true;
                    resp.status = 'success';
                    cases[0].Certification_Log__c += '\n' + JSON.serialize(resp);
                    try{
                        update cases[0];
                    } catch(Exception e2){
                        resp.errorMessage = e2.getMessage();
                        resp.errorCode = 3;
                    }
        }
        else{
          resp.errorMessage = 'Case not found';
          resp.errorCode = 2;
        }
      }
      else{
                resp.errorMessage = 'no merchantId passed';
                resp.errorCode = 1;
      }
    }
    catch(Exception e){
      resp.errorMessage = 'JSON parse error';
      resp.errorCode = 0;
    }
    return resp;
  }
}
