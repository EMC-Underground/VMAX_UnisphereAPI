#!/usr/bin/env ruby
require "rest-client"
require "json"
require "base64"
require "pry-byebug"
require "influxdb"

#######################################
# Set ENV variables for Docker
########################################

uniIP = ENV["uniIP"]
uniPort  = ENV["uniPort"]
uniUser = ENV["uniUser"]
uniPass = ENV["uniPass"]
influxIP = ENV["influxIP"]
influxPort = ENV["influxPort"]
influxUser = ENV["influxUser"]
influxPass = ENV["influxPass"]
influxTable = ENV["influxTable"]
metricsEnv = ENV['metrics']

#########################
# Method: API Post Method
#########################
def rest_post(payload, api_url, auth, cert=nil)
  JSON.parse(RestClient::Request.execute(
    method: :post,
    url: api_url,
    verify_ssl: false,
    payload: payload,
    headers: {
      authorization: auth,
      content_type: 'application/json',
      accept: :json
    }
  ))
end

########################
# Method: API GET Method
########################
def rest_get(api_url, auth, cert=nil)
  response = RestClient::Request.execute(method: :get,
    url: api_url,
    verify_ssl: false,
    headers: {
      authorization: auth,
      accept: :json
    }
  )
  if response.code == 200
      return JSON.parse(response)
  else
      abort("GET request received a #{response.code} error code. Application has not received Symmetrix Keys to obtain metrics. Please see rest_get method in ruby source. Sorry.")
  end
    
end

#################################
# Method: Read settings.json file
#################################
def readSettings(file)
  #puts(file)
  settings = File.read(file)
  JSON.parse(settings)
end



# Create influx instance and connect to InfluxDB
influxdb = InfluxDB::Client.new influxTable, host: influxIP, port: influxPort, username: influxUser, password: influxPass



symIds = []
lastAvail = []
firstAvail = []
noMetrics = []
yesMetrics = []
influxArray = []



# Build our url strings
keys_url = "https://#{uniIP}:#{uniPort}/univmax/restapi/performance/Array/keys"
metrics_url = "https://#{uniIP}:#{uniPort}/univmax/restapi/performance/Array/metrics" 

# Create base 64 encoded auth
auth = Base64.strict_encode64("#{uniUser}:#{uniPass}")

#####################################################
# Make Keys Call to get SYM IDs and Most Recent Date
######################################################

keys_object = rest_get(keys_url, auth, cert=nil)

###################################################
# NOTE: ADD ERROR CHECKING HERE. ENSURE KEYS_OBJECT
# IS A VALID RETURN
####################################################
#################################################
# Build POST Request Body Object from Keys Return
##################################################

# Create array to hold symmetrix IDS and another to hold their last available date
keys_object['arrayInfo'].each do |arrayObj|
        symIds << arrayObj['symmetrixId']
        lastAvail << arrayObj['lastAvailableDate']
        firstAvail << arrayObj['firstAvailableDate']
end

#Start a loop that makes requests and dumps requested info into influx
index = 0

symIds.each do |sym|
    postObject = {'startDate' => lastAvail[index], 'endDate' => lastAvail[index], 'symmetrixId' => sym, 'dataFormat' => 'Average', 'metrics' => metricsEnv}
    # convert object to JSON
    jsonPayload = postObject.to_json
    # Make POST Request
    metrics_object = rest_post(jsonPayload, metrics_url, auth, cert=nil)
#######################################################
# NOTE: ADD ERROR CHECKING HERE. ENSURE METRICS_OBJECT
# IS A VALID RETURN
#######################################################

###################################################################
# BEGIN ERROR CHECKING HERE
#####################################################################
# NOTES: WE NEED TO ANALYZE THE JSON UNISPHERE RETURNS IF/WHEN THE METRICS 
# ARE INACCESSIBLE. ONCE WE CAN SEE THE JSON FROM AN EMPTY METRIC OR
# DEPRECATED METRIC WE CAN ADD THE PROPER ERROR CHECKING FOR RETURN THAT
# HAS NO METRICS
##########################################################################

    # fill reporting arrays to print which arrays found metrics
    if metrics_object['resultList']['result'] == nil
        noMetrics << sym 
    else
        yesMetrics << sym
    end



    # move to next sym if sym ID generated no metrics
    next if metrics_object['resultList']['result'] == nil

#####################################################################
# END ERROR CHECKING
####################################################################

    #grab relevant data from http response
    metricList = metrics_object['resultList']['result']

####################################################
# Organized returned object into influxDB payload
#####################################################
    # collect the data from each metric returned from API
    metricsEnv.each do |metric|
        # get actual value
        newValue = metricList[0][metric]
        # create influx payload
        influxPayload = {series: metric, values: {value: newValue}, tags: {symmetrixId: sym}}
        # push the current metric to the array
        influxArray.push(influxPayload)
    end
    # send array of data points to influx
    influxdb.write_points(influxArray)
    # clear array
    influxArray.clear
    # increment and loop
    index += 1



end
# Print results of symmetrix metrics
# NOTE: ADD ACTUAL METRICS TO RUBY PRINTOUT
if noMetrics.length >0
    puts "The following Symmetrix produced NO metrics: "
    puts noMetrics
end
if yesMetrics.length >0
        puts "The following Symmetrix produced metrics "
    puts yesMetrics  
end

# Clear all arrays
symIds.clear
lastAvail.clear        
firstAvail.clear
noMetrics.clear
yesMetrics.clear
    

