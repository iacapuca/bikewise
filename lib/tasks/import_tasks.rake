desc "initial import from SeeClickFix"
task :seeclickfix_import => :environment do
  import = ImportStatus.find_or_create_by(source: 'seeclickfix')
  import.info_hash[:imported_pages] = [] unless import.info_hash[:imported_pages].present? 
  last_page = 3
  integration = SeeClickFixIntegration.new 
  last_page_issues = integration.get_issues_page(last_page)
  last_updated_at = integration.last_issue_updated_at(last_page_issues)
  last_page = 8 unless last_updated_at > (Time.now - 2.hours)
  integration.make_reports_from_issues_page(last_page_issues)
  # puts "\nProcessing pages up to page #{last_page}"
  pages = (1...(last_page)).to_a
  pages.each do |page|
    next if import.info_hash[:imported_pages].include?(page)
    import.info_hash[:imported_pages] << page
    GetScfReportsWorker.perform_async(page)
  end
  import.info_hash[:imported_pages].uniq!
  import.save
end

desc "initial import from BikeIndex"
task :bikeindex_import => :environment do
  import = ImportStatus.find_or_create_by(source: 'bikeindex')
  integration = BikeIndexIntegration.new 
  time = Time.now - 2.hours
  bike_ids = integration.get_stolen_bikes_updated_since(time)
  bike_ids.each { |id| GetBinxReportWorker.perform_async(id) }
  import.info_hash[:stolen_bikes_to_import] = bike_ids
  import.save
end

desc "Process unprocessed reports"
task :process_reports => :environment do
  report_klasses = ["BinxReport", "ScfReport", "BwReport"]
  report_klasses.each do |klass|
    report_ids = klass.constantize.unprocessed.pluck(:id)
    report_ids.each { |id| ProcessReportsWorker.perform_async(klass, id) }
  end
end

desc "Process unprocessed reports"
task :process_existing_reports => :environment do
  Incident.all.each do |incident|
    incident.incident_reports.each { |r| ProcessReportsWorker.perform_async(r.report.class.name, r.report.id) }
  end
end