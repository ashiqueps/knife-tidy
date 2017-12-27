require 'chef/knife/tidy_base'

class Chef
  class Knife
    class TidyNotify < Knife

      deps do
        require 'ffi_yajl'
        require 'net/smtp'
      end

      banner "knife tidy notify (options)"

      option :smtp_server,
             :short => '-s SERVER_NAME',
             :long => '--smtp_server SERVER_NAME',
             :default => 'localhost',
             :description => 'SMTP Server to be used for emailling reports to organisation admins (defaults to localhost)'

      option :smtp_port,
             :short => '-p SMTP_PORT',
             :long => '--smtp_port SMTP_PORT',
             :default => 25,
             :description => 'SMTP port to be used for emailling reports to organisation admins (defaults to 25)'

      option :smtp_helo,
             :short => '-h SMTP_HELO',
             :long => '--smtp_helo SMTP_HELO',
             :default => 'localhost',
             :description => 'SMTP HELO to be used for emailling reports to organisation admins (defaults to localhost)'

      option :smtp_username,
             :short => '-u SMTP_USERNAME',
             :long => '--smtp_username SMTP_USERNAME',
             :description => 'SMTP Username to be used for emailling reports to organisation admins'

      option :smtp_password,
             :long => '--smtp_password SMTP_PASSWORD',
             :description => 'SMTP Password to be used for emailling reports to organisation admins'

      option :smtp_from,
             :long => '--smtp_from SMTP_FROM',
             :description => 'SMTP From address to be used for emailling reports to organisation admins'

      option :smtp_use_tls,
             :long => '--smtp_use_tls',
              :short => '-t',
              :default => false,
              :boolean => true | false,
              :description => 'Whether TLS should be used for emailling reports to organisation admins (defaults to false if omitted)'


      include Knife::TidyBase

      def run

        reports_dir = tidy.reports_dir
        report_file_suffixes = ["_unused_cookbooks.json", "_cookbook_count.json", "_stale_nodes.json"]
        # Only grab the files matching the report_file_suffixes
        report_files = Dir["#{reports_dir}/*{#{report_file_suffixes.join(',')}}"]

        ui.info "Reading from #{tidy.reports_dir} directory"

        # Fetch list of organisation names from reports directory
        begin
          org_names = reports_files.map{|r_file|r_file.match("#{reports_dir}\/(.*)(#{report_file_suffixes.join('|')})").captures.first}.uniq
        rescue NoMethodError
          ui.stderr.puts "Failed to parse json reports files. Please ensure your reports are valid."
          return
        end
        if config[:org_list]
          filter_orgs = config[:org_list].split(',')
          # Take the intersection of org_names and filter_orgs
          org_names &= filter_orgs
        end

        reports = {}

        # Iterate through list of collected organisations and parse any report files into JSON objects

        unless org_names
          ui.std.puts "No valid org reports found to send notifications. Exiting."
          return
        end

        org_names.each do |org|
          ui.info("Fetching report data for organisation #{org}")
          reports[org] = {}
          report_file_suffixes.each do |report|
            begin
              file_name = "#{reports_dir}/#{org}#{report}"
              ui.info("  Parsing file #{file_name}")
              json_string = File.read(file_name)
              reports[org][report] = FFI_Yajl::Parser.parse( json_string)
            rescue Errno::ENOENT
              ui.info("    Skipping file #{file_name} - not found for organisation #{org}")
              reports[org][report] = {}
            end
          end

          # Fetch a list of admin users for the current organisation
          ui.info("Fetching admins users for organisation #{org}")
          begin
            admins = org_admins(org)
            reports[org]['admins'] = admins.map{|name,data| org_user(org,name) unless name == "pivotal"}
          rescue Net::HTTPServerException
            ui.info("  Cannot fetch admin users for organisation #{org} as it does not exist on the server")
          end

          # Build list of email recipients from the collected admin users (display name and email address of each)
          email_recipients = reports[org]['admins'].map{|admin|{name: admin['display_name'], email: admin['email']} unless admin.nil?}.compact

          # Send a report email to all admin users of the organisation
          ui.info "Sending email reports for organisation #{org}"
          email_content = generate_email(reports,org, email_recipients)
          send_email(email_content,email_recipients)
        end



      end

      private

      def generate_email(report_data,organisation, recipients)
        message = <<MESSAGE_END
From: Knife Tidy <#{config[:smtp_from]}>
To: #{recipients.map{|recipient|"#{recipient[:name]} <#{recipient[:email]}>"}.join(", ")}
Content-type: text/html
Subject: Knife Tidy Cleanup Report for Organisation "#{organisation}"

The following reports were generated by <a href="https://github.com/chef-customers/knife-tidy">knife-tidy</a>, and contain a list of unused cookbooks and stale nodes for the Chef server organisation "#{organisation}"
#{generate_total_cookbook_table(report_data,organisation)}
<br/>
#{generate_unused_cookbook_table(report_data,organisation)}
<br/>
#{generate_node_table(report_data,organisation)}
MESSAGE_END

        message
      end

      def generate_total_cookbook_table(report_data, organisation)
        table_start = "<h2>Total Versions by Cookbook</h2><p>This table contains the count of versions of each cookbook stored on the Chef Server.<p><table border='1' cellpadding='1' cellspacing='0'>"
        table_end = "</table>"
        header_string = "<tr><th>Cookbook Name</th><th>Total Version Count</th></tr>"
        table_body = report_data[organisation]['_cookbook_count.json'].map{|cookbook_name,cookbook_count|"<tr><td>#{cookbook_name}</td><td>#{cookbook_count}</td></tr>"}.join("\n")
        table_start + header_string + table_body + table_end
      end

      def generate_total_unused_table(report_data, organisation)
        table_start = "<h2>Unused Cookbooks</h2><p>This table contains cookbook names and the count of their versions that are not currently in the runlists of any nodes.<p><table border='1' cellpadding='1' cellspacing='0'>"
        table_end = "</table>"
        header_string = "<tr><th>Cookbook Name</th><th>Unused Versions</th></tr>"
        table_body = report_data[organisation]['_unused_cookbooks.json'].map{|cookbook_name,cookbook_versions|"<tr><td>#{cookbook_name}</td><td>#{cookbook_versions.join("<br>")}</td></tr>"}.join("\n")
        table_start + header_string + table_body + table_end
      end

      def generate_node_table(report_data,organisation)
        table_start = "<h2>Stale Nodes</h2><p>This table contains nodes that have not checked in to the Chef Server in #{report_data[organisation]['_stale_nodes.json']['threshold_days']} days.<p><table border='1' cellpadding='1' cellspacing='0'>"
        table_end = "</table>"
        header_string = "<tr><th>Node Name</th></tr>"
        table_body = report_data[organisation]['_stale_nodes.json']['list'].map{|node_name|"<tr><td>#{node_name}</td></tr>"}.join("\n")
        table_start + header_string + table_body + table_end
      end

      def send_email(mail_content,recipients)
        smtp = Net::SMTP.new(config[:smtp_server],config[:smtp_port])
        smtp.enable_starttls if config[:smtp_use_tls]
        smtp.start(config[:smtp_helo],config[:smtp_username],config[:smtp_password],:login) do |server|
          server.send_message(mail_content, config[:smtp_from], recipients.map{|recipient|recipient[:email]})
        end
      end

      def org_admins(org)
        admins = {}
        rest.get("/organizations/#{org}/groups/admins")["users"].each do |name|
          admins[name] = {}
        end
        admins
      end

      def org_user(org,username)
        rest.get("/organizations/#{org}/users/#{username}")
      end
    end
  end
end
