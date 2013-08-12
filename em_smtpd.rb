require 'eventmachine'
require 'mail'

HEADER_TO_CLEAN =  ['User-Agent', 'X-Enigmail', 'X-Mailer', 'X-Originating-IP']


def clean_message(raw_mail)
  mail = Mail.new(raw_mail[:source])


  puts "==> Before anon"
  p mail

  HEADER_TO_CLEAN.each do |field|
    mail.header[field] = nil if mail.header[field]
  end

  new_received = mail.header[:Received].to_s.sub(/(from)[^;]*(.*)/, '\1 [127.0.0.1] (localhost [127.0.0.1])\2')
  mail.header[:Received] = nil
  mail.header[:Received] = new_received

  puts "==> After anon"
  p mail

options = {:address => '127.0.0.1',
           :port => '2001'}
  # Send mail
  mail.delivery_method :smtp, options
  mail.deliver
end

class EmailServer < EM::P::SmtpServer 
  def self.start(host = 'localhost', port = 2000)
    require 'ostruct'
    @server = EM.start_server host, port, self
  end

  def self.stop
    if @server
      EM.stop_server @server
      @server = nil
    end
  end

  def self.running?
    !!@server
  end

  # We override EM's mail from processing to allow multiple mail-from commands
  # per [RFC 2821](http://tools.ietf.org/html/rfc2821#section-4.1.1.2)
  def process_mail_from sender
    if @state.include? :mail_from
      @state -= [:mail_from, :rcpt, :data]
      receive_reset
    end

    super
  end

  def current_message
    @current_message ||= {}
  end

  def receive_reset
    @current_message = nil
    true
  end

  def receive_sender(sender)
    current_message[:sender] = sender
    true
  end

  def receive_recipient(recipient)
    current_message[:recipients] ||= []
    current_message[:recipients] << recipient
    true
  end

  def receive_data_chunk(lines)
    current_message[:source] ||= ""
    current_message[:source] << lines.join("\n")
    true
  end

  def receive_message
    #MailCatcher::Mail.add_message current_message
    clean_message(current_message)

    puts "==> SMTP: Received message from '#{current_message[:sender]}' (#{current_message[:source].length} bytes)"
    true
  rescue
    puts "*** Error receiving message: #{current_message.inspect}"
    puts " Exception: #{$!}"
    puts " Backtrace:"
    $!.backtrace.each do |line|
      puts " #{line}"
    end
    puts " Please submit this as an issue at http://github.com/sj26/mailcatcher/issues"
    false
  ensure
    @current_message = nil
  end

end

EM.run{ EmailServer.start }
