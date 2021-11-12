include ClientsHelper
include Sso
class Sso::SsoController < ApplicationController
  before_action :get_user_info
  before_action :find_sso_user, only: [:sso_login, :sso_logout]
  
  def sso_signup
    I18n.locale = "en"
    @client = Client.new(new_client_params(@user_info, @domain_setting))
    begin
      @client.save!
      update_default_client_setting(@client, @domain_setting) if @domain_setting.present? && @domain_setting.default_setting?
      create_all_services(@client)
      render json: @client.user, status: :created
    rescue Exception => e
      render json: { status: :forbidden, error: e.message }, status: 403
    end
  end

  def sso_login
    sign_in :user, @sso_user
    session[:logout_redirect_url] = @user_info['logout_redirect_url']
    redirect_to signin_redirect(@sso_user), notice: "login successfully"
  end

  def sso_logout
    sign_out
    redirect_to @user_info['logout_redirect_url']
  end

  protected
  
  def get_user_info
    decode_jwt_string(params["token"])
  end
  
  def find_sso_user
    @sso_user = User.find_by( "email =  ?", @user_info['email'].to_s)
    if @sso_user.nil?
      return render json: { status: :not_found, error: 'email did not match' }, status: 404
    end
  end
end
