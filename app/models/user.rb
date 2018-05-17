class User < ActiveRecord::Base

  # For UK subscriber access
  include ActiveModel::Validations #required because some before_validations are defined in devise
  extend ActiveModel::Callbacks #required to define callbacks
  extend Devise::Models
  define_model_callbacks :validation #required by Devise
  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :trackable, :validatable, :remote_authenticatable, :authentication_keys => [:login]

  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable,
  # :lockable, :timeoutable and :omniauthable

  # Validate username
  validates :username, :presence => true
  validates :username,
    :uniqueness => {
      :case_sensitive => false
    }

  # How to validate the format of username (not used)
  # validates_format_of :username, :with => /^[-_a-z0-9]+$/, :message => "Your username can only include lower case letters and numbers."

  # join-model for purchases
  has_many :purchases
  has_many :issues, :through => :purchases

  has_many :guest_passes, :dependent => :destroy
  has_many :articles, :through => :guest_passes

  # join-model for favourites
  has_many :favourites, :dependent => :destroy
  has_many :articles, :through => :favourites

  # association for subscriptions
  has_many :subscriptions
  has_many :payment_notifications

  # parent-child relationships for institutional accounts
  belongs_to :parent, :class_name => 'User', :foreign_key => 'parent_id'
  has_many :children, :class_name => 'User', :foreign_key => 'parent_id', :dependent => :destroy

  # Send a welcome email after a user is created
  after_create :send_welcome_mail

  # This only allowed 1 user to have a blank email address, so we now give out fake emails for student users
  # def email_required?
  #   # if it DOESN'T have a parent, it DOES need an email
  #   return self.parent.nil?
  # end

  def send_welcome_mail
    if uk_user?
      if Rails.env.production?
        begin
          UserMailer.delay.user_signup_confirmation_uk(self)
          ApplicationHelper.start_delayed_jobs
        rescue Exception
          logger.error "500 - Email server is down..."
        end
      else
        logger.info "SEND_WELCOME_MAIL UK user would happen on production."
      end
    else
      if Rails.env.production?
        begin
          UserMailer.delay.user_signup_confirmation(self)
          ApplicationHelper.start_delayed_jobs
        rescue Exception
          logger.error "Email server is down..."
        end
      else
        logger.info "SEND_WELCOME_MAIL would happen on production."
      end
    end
  end

  def self.find_for_database_authentication(warden_conditions)
    conditions = warden_conditions.dup
    if login = conditions.delete(:login)
      where(conditions.to_hash).where(["lower(username) = :value OR lower(email) = :value", { :value => login.downcase }]).first
    else
      where(conditions.to_hash).first
    end
  end

  # Virtual attribute for authenticating by either username or email
  # This is in addition to a real persisted field like 'username'
  attr_accessor :login
  
  # CSV exporting
  comma do

    id
    username
    email
    expiry_date 'expiry_date'
    is_recurring? 'is_recurring'
    was_recurring? 'was_recurring'
    has_paper_copy? 'has_paper_copy'
    has_paper_only? 'has_paper_only'
    institution?

    last_subscription_including_cancelled :paypal_first_name => 'paypal_first_name'
    last_subscription_including_cancelled :paypal_last_name => 'paypal_last_name'
    last_subscription_including_cancelled :paypal_email => 'paypal_email'
    last_subscription_including_cancelled :paper_copy => 'paper_copy'
    last_subscription_including_cancelled :paper_only => 'paper_only'
    last_subscription_including_cancelled :purchase_date => 'purchase_date'
    last_subscription_including_cancelled :valid_from => 'valid_from'
    last_subscription_including_cancelled :duration
    last_subscription_including_cancelled :cancellation_date => 'cancellation_date'
    last_subscription_including_cancelled :refunded_on => 'refunded_on'
    last_subscription_including_cancelled :paypal_country_code => 'paypal_country_code'
    last_subscription_including_cancelled :paypal_country_name => 'paypal_country_name'

    uk_id 'uk_id'
    uk_expiry 'uk_expiry'

  end

  #Override to_s to show user details instead of #string
  def to_s
    "#{username}"
  end

  def subscriptions
    if self.parent
      return parent.subscriptions
    else
      return super
    end
  end

  def subscription_valid?
    if self.parent
      host = self.parent
    else
      host = self
    end
    return host.subscriptions.collect{|s| s.is_current?}.include?(true)
  end

  def subscription_lapsed?
    return ( not self.subscriptions.empty? and not self.subscription_valid? )
  end

  def subscriber?
    if uk_user?
      # UK subscriber
      return uk_subscription_valid?
    else
      # Local subscriber
      return subscription_valid?
    end
  end

  def paper_only_subscription_valid?
    return self.subscriptions.select{|s| s.paper_only? == true}.collect{|s| s.is_current?}.include?(true)
  end

  def uk_user?
    not uk_id.nil?
  end

  def uk_subscription_valid?
    if uk_expiry > DateTime.now or subscription_valid?
      return true
    end
  end

  def is_recurring?
    # TODO: need to differentiate between the first recurring subscription and the paypal IPN recurrances.
    return self.subscriptions.collect{|s| s.is_recurring?}.include?(true)
  end

  def was_recurring?
    return self.subscriptions.collect{|s| s.was_recurring?}.include?(true)
  end

  def has_cancelled_recurring?
    return self.subscriptions.collect{|s| s.cancellation_date.nil?}.include?(false)
  end

  def has_refunded_recurring?
    return self.subscriptions.collect{|s| s.refunded_on.nil?}.include?(false)
  end

  def has_paper_copy?
    return self.current_subscriptions.collect{|s| s.paper_copy}.include?(true)
  end

  def has_paper_only?
    return self.current_subscriptions.collect{|s| s.paper_only}.include?(true)
  end

  def expiry_date
    if uk_user?
      # Check for local subscriptions
      rails_expiry = self.subscriptions.collect{|s| s.expiry_date}.sort.last

      if rails_expiry and uk_expiry
        # Return the latest UK or Aus subscription
        return [uk_expiry, rails_expiry].max
      elsif rails_expiry
        return rails_expiry
      elsif uk_expiry
        return uk_expiry
      else
        return nil
      end
    else
      # cancelled subscriptions taken into account by s.expiry_date
      if self.parent
        host = self.parent
      else
        host = self
      end
      return host.subscriptions.collect{|s| s.expiry_date}.sort.last
    end
  end

  def expiry_date_paper_only
    return self.current_subscriptions.select{|s| s.paper_only? == true}.collect{|s| s.expiry_date_paper_only}.sort.last
  end

  def expiry_date_including_ios(request)
    ios_expiry = request_has_valid_itunes_receipt(request)
    logger.info "iOS expiry: #{ios_expiry}"
    logger.info "Rails expiry: #{expiry_date}"
    if ios_expiry
      if expiry_date
        if ios_expiry.to_date > expiry_date.to_date
          logger.info "Returning iOS"
          return ios_expiry
        else
          logger.info "Returning Rails"
          return expiry_date
        end
      else
        logger.info "Returning iOS"
        return ios_expiry
      end
    elsif expiry_date
      logger.info "Returning Rails"
      return expiry_date
    else
      return nil
    end
  end

  def recurring_subscription
    return self.subscriptions.select{|s| s.is_recurring?}.sort{|a,b| a.expiry_date <=> b.expiry_date}.last
  end

  def first_recurring_subscription(profile)
    logger.info("looking for subscription with profile: #{profile}")
    sub = self.subscriptions.select{|s| (s.paypal_profile_id == profile)}.sort{|a,b| a.purchase_date <=> b.purchase_date}.first
    if sub
      logger.info("found #{sub.id}")
    else
      logger.info("not found")
    end
    sub
  end

  def recurring_subscriptions(recurring_payment_id)
    # Return all the subscriptions that have this paypal profile id
    return self.subscriptions.select{|s| (s.paypal_profile_id == recurring_payment_id)}.sort{|a,b| a.purchase_date <=> b.purchase_date}
  end

  def last_subscription
    return self.current_subscriptions.sort{|a,b| a.expiry_date <=> b.expiry_date}.last
  end

  def last_subscription_including_cancelled
    return self.subscriptions.sort{|a,b| a.expiry_date_excluding_cancelled <=> b.expiry_date_excluding_cancelled}.last
  end

  def current_subscription
    return self.current_subscriptions.sort{|a,b| a.expiry_date <=> b.expiry_date}.last
  end

  def current_subscriptions
    return self.subscriptions.select{|s| s.is_current?}
  end

  def refunds_due
    refund = self.subscriptions.collect{|s| 
      if s.refunded_on
        next 0
      else
        next (s.refund or 0)
      end
    }
    return refund.sum
  end

  def user_type
    t = "Guest"
    if admin?
      t = "Admin"
    elsif institution
      t = "Institution"
    elsif parent
      t = "Student"
    elsif subscriber?
      t = "Subscriber"
    end
    if uk_id
      t += " (UK)"
    end
    if has_paper_only?
      t = "Paper Subscriber"
    end
    "#{t}"
  end

  def guest?
    return id.nil?
  end

  private

  def self.sorted_by(column, direction)
    direction = sanitize_sql(direction) ? sanitize_sql(direction) : 'desc'
    column = sanitize_sql(column) ? sanitize_sql(column) : 'created_at'
    order("#{column} #{direction}")
  end

  def request_has_valid_itunes_receipt(request)
    if !request.post?
      return nil
    end

    # send the request to itunes connect

    if Rails.env.production?
      itunes_url = ENV["ITUNES_VERIFY_RECEIPT_URL_PRODUCTION"]
    else
      itunes_url = ENV["ITUNES_VERIFY_RECEIPT_URL_DEV"]
    end
    logger.info "iTunes URL: #{itunes_url}"

    uri = URI.parse(itunes_url)
    http = Net::HTTP.new(uri.host, uri.port)

    json = { "receipt-data" => request.raw_post, "password" => ENV["ITUNES_SECRET"] }.to_json
    http.use_ssl = true
    api_response, data = http.post(uri.path,json)

    # Do a first check to see if the receipt is valid from iTunes
    if JSON.parse(api_response.body)["status"] != 0
      logger.warn "receipt-data: #{request.raw_post}"
      logger.warn "ITUNES RECEIPT ERROR"
      logger.warn "api_response.body"
      return nil
    end

    # Check purchased subscriptions from receipts
    subscription_receipt_valid = false

    expiry_date_from_itunes = latest_subscription_expiry_from_recepits(api_response.body)

    if expiry_date_from_itunes > DateTime.now
      subscription_receipt_valid = true
    end

    # Pass on the expiry date or nil
    if subscription_receipt_valid
      logger.info "This receipt has a valid subscription."
      return expiry_date_from_itunes
    else
      logger.warn "This receipt doesn't include access to this article."
      return nil
    end
  end

  def latest_subscription_expiry_from_recepits(response)
    purchases = JSON.parse(response)['receipt']['in_app']

    subscriptions = []
    latest_expiry = "0"

    purchases.each do |item|
      if item['product_id'].include?('month')
        if item['expires_date_ms'].nil?
          # The subscription is non-renewing, generate :expires_date_ms for it.
          subscription_duration = item['product_id'][0..1].to_i
          item['expires_date_ms'] = ((Time.at(item['original_purchase_date_ms'].to_i / 1000).to_datetime + subscription_duration.months).to_i * 1000).to_s
          logger.info "Non-renewing subscription, synthesized date: (#{item['expires_date_ms']})"
        end
        subscriptions << item
        # TODO: check if they already have a subscription in Rails, if not, purchase one
      end
    end

    logger.info "Susbcriptions purchased: "
    logger.info subscriptions

    if not subscriptions.empty?
      latest_expiry = subscriptions.sort_by{ |x| x["expires_date_ms"]}.last["expires_date_ms"]
    end

    sec = (latest_expiry.to_f / 1000).to_s

    latest_sub_date = DateTime.strptime(sec, '%s')

    logger.info "Latest subscription expiry date: "
    logger.info latest_sub_date

    return latest_sub_date
  end

  def self.update_admin_users_csv
    Settings.users_csv = User.uncached do
      User.order(:email).all.to_comma()
    end
  end

  def self.find_by_whitelist(ip)
    # sql one liner to handle both CIDR and IP ranges
    query = ActiveRecord::Base.send(:sanitize_sql_array, ["with ip as (select ?::inet as value) select * from (select *, regexp_split_to_table(ip_whitelist,E',') as pattern from users) as expanded, regexp_split_to_array(expanded.pattern,E'-') as range where (expanded.pattern <> '' and expanded.pattern !~ '-' and (select value from ip) <<= expanded.pattern::inet) or (expanded.pattern ~ '-' and ((select value from ip) between range[1]::inet and range[2]::inet)) limit 1", ip])
    begin
      self.find_by_sql(query)
    rescue
      alert_text = ApplicationHelper.bad_ip_alert_text
      logger.error alert_text
      if not Settings.admin_alert or Settings.admin_alert == 0
        Settings.admin_alert = 1
      end
      return nil
    end
  end

end
