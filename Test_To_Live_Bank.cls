/**
 * Test_To_Live_Bank web service integration
 * Created by Ivaylo Iliev on 24.02.21 г..
 * Modifed by Ivaylo Nikolov on 31.03.2022 - replacing Certification_Log__c with Test_to_Live_Bank_Log__c
 *
 * In order for the callout to work properly you need to have a custom setting configured as follows:
 * 1. Create custom settings group named Test_To_Live_Bank_Settings
 * 2. Add custom field named Value with type Text and size 255
 * 3. Add record with Name=Endpoint and Value__c=<URL of the web service>
 * 4. Add record with Name=ConnectionTimeout and Value__c=120000 (can be changed if needed)
 */

public with sharing class Test_To_Live_Bank {
    /**
     * Perform callout to HTTP service
     * @param clientIds List of client IDs to perform a callout for
     */
    @InvocableMethod ( Label='Test To Live Bank' Description='Perform call to Test To Live Bank' )
    public static void execute( List<String> clientIds ) {
        System.debug('Client IDs in Invocable: ' + clientIds);
        // Read settings for the callout
        Map<String, String> settingsMap = getSettings();

        // Iterate over the list of client IDs and perform callout for each of them
        for( String clientId : clientIds ) {
            // Construct client ID endpoint for callout
            String endPoint = settingsMap.get( 'Endpoint' ).trim();

            if( !endPoint.endsWith( '/' ) ) {
                endPoint += '/';
            }

            endPoint += clientId;

            // Perform HTTP request
            performCallout( clientId, endPoint, settingsMap.get( 'ConnectionTimeout' ).trim() );
        }
    }

    /**
     * Separate the transactions of settings extraction and callout to external service
     * @param clientId Id of the client from GW_Name object
     * @param endpoint Endpoint to call
     * @param timeout Connection timeout
     */
    @Future ( Callout=true )
    public static void performCallout( String clientId, String endpoint, String timeout ) {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setEndpoint( endpoint );
        request.setMethod( 'PUT' );
        request.setTimeout( Integer.valueOf( timeout ) );
        HttpResponse response = http.send( request );

        // Get the response and save it to the Case object
        String message = 'Response status: ' + response.getStatus() + '\n\nResponse body: ' + response.getBody();
        logToCase(clientId, message);
    }

    /**
     * Read custom settings from Test_To_Live_Bank_Settings__c
     *
     * @return Map<String, String> of custom settings for Test_To_Live_Bank callout
     */
    @TestVisible
    private static Map<String, String> getSettings() {
        Map<String, String> settingsMap = new Map<String, String>();
        Map<String, SObject> settingList = Test_To_Live_Bank_Settings__c.getAll();
        for( String key : settingList.keySet() ) {
            settingsMap.put( key, String.valueOf( settingList.get( key ).get( 'Value__c' ) ) );
        }
        return settingsMap;
    }

    @TestVisible
    private static void logToCase( String clientId, String message ) {
        RecordType recordType = [SELECT Id, Name, DeveloperName FROM RecordType WHERE SobjectType='Case' AND DeveloperName = 'Configuration' LIMIT 1];

        List<Case> casesForLogging = [
                SELECT Id,
                        Test_to_Live_Bank_Log__c,
                        GW_Name__r.Client_ID__c
                FROM Case
                WHERE GW_Name__r.Client_ID__c = :clientId
                AND RecordTypeId = :recordType.Id
        ];

        for(Case logCase : casesForLogging ){
            logCase.Test_to_Live_Bank_Log__c = message;
        }

        update casesForLogging;
    }
}
