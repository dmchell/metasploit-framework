##
# This module requires Metasploit: http//metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

require 'msf/core'

class Metasploit3 < Msf::Auxiliary

  include Msf::Auxiliary::Report
  include Msf::Auxiliary::Scanner
  include Msf::Auxiliary::NATPMP

  def initialize
    super(
      'Name'        => 'NAT-PMP External Address Scanner',
      'Description' => 'Scan NAT devices for their external address using NAT-PMP',
      'Author'      => 'Jon Hart <jhart[at]spoofed.org>',
      'License'     => MSF_LICENSE
    )

  end

  def run_host(host)
    begin
      udp_sock = Rex::Socket::Udp.create({
        'LocalHost' => datastore['CHOST'] || nil,
        'Context'   => {'Msf' => framework, 'MsfExploit' => self}
      })
      add_socket(udp_sock)
      vprint_status "#{host}:#{datastore['RPORT']} - NATPMP - Probing for external address"

      udp_sock.sendto(Rex::Proto::NATPMP.external_address_request, host, datastore['RPORT'].to_i, 0)
      while (r = udp_sock.recvfrom(12, 1.0) and r[1])
        handle_reply(host, r)
      end
    rescue ::Interrupt
      raise $!
    rescue ::Rex::HostUnreachable, ::Rex::ConnectionTimeout, ::Rex::ConnectionRefused
      nil
    rescue ::Exception => e
      print_error("#{host}:#{datastore['RPORT']} Unknown error: #{e.class} #{e}")
    end
  end

  def handle_reply(host, pkt)
    return if not pkt[1]

    if(pkt[1] =~ /^::ffff:/)
      pkt[1] = pkt[1].sub(/^::ffff:/, '')
    end

    (ver, op, result, epoch, external_address) = Rex::Proto::NATPMP.parse_external_address_response(pkt[0])

    if (ver == 0 && op == 128 && result == 0)
      print_status("#{host} -- external address #{external_address}")
      # report its external address as alive
      if inside_workspace_boundary?(external_address)
        report_host(
          :host   => external_address,
          :state => Msf::HostState::Alive
        )
      end
    else
      print_error("#{host} -- unexpected version/opcode/result/address: #{ver}/#{op}/#{result}/#{external_address}")
    end

    # report the host we scanned as alive
    report_host(
      :host   => host,
      :state => Msf::HostState::Alive
    )

    # report NAT-PMP as being open
    report_service(
      :host   => host,
      :port   => pkt[2],
      :proto  => 'udp',
      :name   => 'natpmp',
      :state  => Msf::ServiceState::Open
    )
  end
end
