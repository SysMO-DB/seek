require 'libxml'
require 'csv'
require 'simple-spreadsheet-extractor'
require 'open-uri'

class DataFuseController < ApplicationController
  include Seek::MimeTypes
  include Seek::Models::ModelExtraction
  include SysMODB::SpreadsheetExtractor
  include Seek::JWS::DataFuseMethods

  before_filter :login_required
  before_filter :is_user_admin_auth

  @@model_builder = Seek::JWS::Builder.new

  def data_file_csv

    element=params[:element]
    data_file=DataFile.find_by_id(params[:id])

    last_sheet = find_last_sheet_index(data_file)
    csv = spreadsheet_to_csv(open(data_file.content_blob.filepath),last_sheet,true)

    render :update do |page|
      if data_file.try :can_download?
        page.replace_html element, :partial=>"data_fuse/csv_view", :locals=>{:csv=>csv}
      else
        page.replace_html element, :text=>"#{t('data_file')} not found, or not authorized to examine"
      end
    end

  end

  def preview_model
    element=params[:element]
    model = Model.find_by_id(params[:id])
    render :update do |page|
      page.replace_html element, :partial=>"models/resource_list_item", :locals=>{:resource=>model}
    end
  end

  def preview_data_file
    element=params[:element]
    df = DataFile.find_by_id(params[:id])
    render :update do |page|
      page.replace_html element, :partial=>"data_files/resource_list_item", :locals=>{:resource=>df}
    end
  end



  def matching_data_files
    element=params[:element]
    model = Model.find_by_id(params[:id])

    @matching_data_files = model.matching_data_files(true)
    render :update do |page|
      page.replace_html element, :partial=>"matching_data_select"
    end
  end

  def show
    @models=Model.all.select{|m| m.can_download? && m.is_jws_supported?}
    respond_to do |format|
      format.html
    end
  end

  def assets_selected
    @data_file = DataFile.find(params[:data_file_id])
    @model=Model.find(params[:model_id])
    params[:parameter_keys] ||= {}

    #FIXME: temporary way of making sure it isn't exploited to get at data. Should never get here if used through the UI
    raise Exception.new("Unauthorized") unless @model.can_download? && @data_file.can_download?

    @parameter_keys = params[:parameter_keys].keys

    @matching_csv,@matching_keys = matching_csv(@data_file,@parameter_keys)

    respond_to do |format|
      format.html
    end
  end

  def matching_csv data_file,parameter_keys
    last_sheet_index = find_last_sheet_index(data_file)
    csv = spreadsheet_to_csv(open(data_file.content_blob.filepath),last_sheet_index,true)

    #FIXME: temporary way of making sure it isn't exploited to get at data. Should never get here if used through the UI
    raise Exception.new("Unauthorized") unless @model.can_download?

    resolve_model_parameter_keys parameter_keys,csv

  end

  def submit
    @model=Model.find(params[:model_id])
    parameter_csv=params[:parameter_csv]
    matching_keys=params[:matching_keys]

    @results = submit_parameter_values_to_jws_online @model,matching_keys,parameter_csv

    respond_to do |format|
      format.html
    end
  end



  def find_last_sheet_index data_file
    #FIXME: this currently uses the XML to find the number of sheets. The spreadsheet extractor will be updated to provide a summary including this
    #information in the future which will be more efficient

    xml = spreadsheet_to_xml(open(data_file.content_blob.filepath))

    parser = LibXML::XML::Parser.string(xml)
    doc = parser.parse
    doc.root.namespaces.default_prefix="ss"

    doc.find("//ss:workbook/ss:sheet").count

  end

  def parameter_keys

    element=params[:element]
    model=Model.find_by_id(params[:id])

    ps=model.parameters_and_values.keys

    render :update do |page|
      if model.try :can_download?

        page.replace_html element, :partial=>"data_fuse/parameter_keys", :locals=>{:keys=>ps}
      else
        page.replace_html element, :text=>"#{t('model')} not found, or not authorized to examine"
      end
    end
  end

  def view_result_csv
    url = params[:url]
    @csv=open(url).read
    respond_to do |format|
      format.html
    end
  end

  def resolve_model_parameter_keys parameter_keys, csv

    matching_columns = {}
    matched_keys = []
    matching_csv = []

    CSV.parse(csv).each do |row|
      matched_row = []
      row.each_with_index do |v, i|
        if matching_columns[i]
          matched_row << v
        end
        k = matching_key? parameter_keys, v
        if k
          matched_row << k
          matching_columns[i]=k
          matched_keys << k
        end
      end
      matching_csv << matched_row unless matched_row.empty?
    end

    result = CSV.generate do |out|
      matching_csv.each do |row|
        out << row
      end
    end

    return result, matched_keys

  end

  def matching_key? parameter_keys, v
    v if parameter_keys.include?(v)
  end

end
