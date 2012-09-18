class PaymentNotificationsController < ApplicationController
	
	protect_from_forgery :except => [:create]

	def create
		PaymentNotification.create!(:params => params, :user_id => params[:invoice], :status => params[:payment_status], :transaction_id => params[:txn_id], :transaction_type => params[:txn_type] )
    	render :nothing => true
	end
end
