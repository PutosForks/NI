class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable,
  # :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable, :authentication_keys => [:login]

  # join-model for purchases
  has_many :purchases
  has_many :issues, :through => :purchases

  def self.find_first_by_auth_conditions(warden_conditions)
    conditions = warden_conditions.dup
    if login = conditions.delete(:login)
      where(conditions).where(["lower(username) = :value OR lower(email) = :value", { :value => login.downcase }]).first
    else
      where(conditions).first
    end
  end

  def subscription_valid?
    expirydate and (expirydate > Date.today)
  end

  # Virtual attribute for authenticating by either username or email
  # This is in addition to a real persisted field like 'username'
  attr_accessor :login

  # Setup accessible (or protected) attributes for your model
  attr_accessible :issue_ids, :login, :username, :expirydate, :admin, :subscriber, :email, :password, :password_confirmation, :remember_me
  # attr_accessible :title, :body

  #Override to_s to show user details instead of #string
  def to_s
    "#{username}"
  end

  def user_type
    t = "Guest"
    if admin?
      t = "Admin"
    elsif subscriber?
      t = "Subscriber"
    end
    "#{t}"
  end


end
