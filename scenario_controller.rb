require 'bulk_apply/scenario_bulk_apply'

include Utils

class ScenarioController < AdminController
  include SortableController
  include ScenarioConcern
  include HierarchyConcern

  SORT_COLS = {
      Scenario.name => ['index', 'name'].push(Scenario.column_names),
      User.name => ['users', 'last_name'],
      Assessment.name => ['assessments', 'name'],
      Report.name => ['reports', 'name'],
      ProjectFile.name => ['project_files', 'name'],
      WorkflowTask.name => ['workflow_tasks', 'name']
  }
  DEFAULT_SORT = SORT_COLS[Scenario.name].push(['name'])
  helper_method :sort_column, :sort_direction


  def index
    default_search = SearchFilter.default_scenario_index_filter
    search_result = SearchFilter.resolve(current_user, self.class.name, 'index', params, default_search)

    @scenarios = Scenario.index_load(search_result.filter, get_sort(Scenario.name), params[:page], current_user)
    @filter_id = search_result.id

    @path = 'scenario_index'

    @detail_path = nil
    if authorized_action?(@session_user, 'create')
      @detail_path = edit_scenario_path('%id%')
    end

    render layout: false
  end

  def export
    default_search = SearchFilter.default_scenario_index_filter
    search_result = SearchFilter.resolve(current_user, self.class.name, 'index', params, default_search)

    if nil_or_blank(params[:submit])
      export_buffer = Scenario.export_data_in_csv(current_user, search_result.filter, get_sort(Scenario.name), false)
      send_data export_buffer, :filename => list_export_file_name(nil, '-scenarios'), :type => 'application/vnd.ms-excel', :disposition => 'attachment'
    else
      Scenario.delay(priority: 30, queue: 'slow').export_data_in_csv(current_user, search_result.filter, get_sort(Scenario.name), true)
      respond_to do |format|
        flash["success"] = 'Scenario List export was scheduled.  You will receive an email with results when it is done.'
        format.js
      end
    end
  end
  
  def new
    @form_action = 'create'
    @scenario = Scenario.new
    @content_configuration = ContentConfiguration.new
    @resource_select_options = Resource.account_for_select(nil)

    render layout: false
  end

  def edit
    @active_tag = 'tab1'
    @form_action = 'update'
    @scenario = Scenario.find_by(id: params[:id])
    @content_configuration = @scenario.content_configuration
    @resource_select_options = Resource.account_for_select(@scenario.account_id)

    @score_override = ScoreOverride.find_by(id: params[:id])


    render layout: false
  end

  def users
    @active_tag = 'tab4'
    @scenario = Scenario.find_by(id: params[:id])
    @detail_path = edit_user_path('%id%')
    @sort_model = User.new

    @users = @scenario.users.where(deleted_at: nil)
                 .order(get_sort(@sort_model))
                 .page(params[:page])
  end

  def assessments
    @active_tag = 'tab5'
    @scenario = Scenario.find_by(id: params[:id])
    @sort_model = Assessment.new
    @detail_path = assessment_properties_path('%id%')

    @assessments = @scenario.assessments.where(deleted_at: nil)
                       .order(get_sort(@sort_model))
                       .page(params[:page])
  end

  def announce_scenario
    @active_tag = 'tab1'
    @success = true
    @scenario = Scenario.lookup_by_id(params[:id])
    @success = @scenario.announce
    flash["success"] = 'Scenario was successfully announced.' if @success
    flash["danger"] = 'No users to announce scenario to.' unless @success
  end

  def send_upload_reminder
    @active_tag = 'tab1'
    @success = true
    @scenario = Scenario.lookup_by_id(params[:id])
    @success = @scenario.send_upload_reminder
    respond_to do |format|
      flash["success"] = 'Video upload reminder email successfully sent.' if @success
      flash["danger"] = 'No users to announce scenario to.' unless @success
      format.js 
    end
  end

  def update
    @form_action = 'update'
    @scenario = Scenario.find_by(id: params[:id])
    @content_configuration = @scenario.content_configuration
    @scenario.assign_attributes(scenario_params)
    @scenario.tag_ids = params[:tag_ids]
    @scenario.start_date = Utils.string_to_date(params[:start_date], '%m-%d-%Y').noon unless nil_or_blank params[:start_date]
    @scenario.end_date = Utils.string_to_date(params[:end_date], '%m-%d-%Y').midnight unless nil_or_blank params[:end_date]
    @resource_select_options = Resource.account_for_select(@scenario.account_id)
    @content_configuration.assign_attributes(properties_content_configuration_params)
    Scenario.validate_content_configuration_properties(@content_configuration)
    @success = @scenario.valid? && !@content_configuration.errors.any?

    if @success
      @content_configuration.save
      @scenario.save
      # ADMIN-2802 Suppress scenario update emails till the time proper email flow is worked out
      # @scenario.announce if @scenario.status.is_in_progress_status
      Scenario.delay(queue: 'normal').update_aging_scenarios
      flash["success"] = 'Scenario was successfully updated.'
    else
      flash["danger"] = 'Scenario update failed!'
    end
  end

  def form_reload
    @form_action = nil_or_blank(params[:id]) ? 'create' : 'update'
    @scenario = nil_or_blank(params[:id]) ? Scenario.new : Scenario.find(params[:id])

    @content_configuration = ContentConfiguration.new
    @scenario.start_date = Utils.string_to_date(params[:start_date], '%m-%d-%Y') unless nil_or_blank params[:start_date]
    @scenario.end_date = Utils.string_to_date(params[:end_date], '%m-%d-%Y') unless nil_or_blank params[:end_date]
    @scenario.tag_ids = params[:tag_ids]
    @scenario.assign_attributes(scenario_params)
    @resource_select_options = Resource.account_for_select(scenario_params[:account_id]) if scenario_params[:account_id]
    @content_configuration.assign_attributes(properties_content_configuration_params)
  end

  def properties
    @active_tag = 'tab1'
    @form_action = 'update'
    @scenario = Scenario.find_by(id: params[:id])
    @resource_select_options = Resource.account_for_select(@scenario.account_id)
    @content_configuration = @scenario.content_configuration

    render layout: false
  end

  def process_settings
    @active_tag = 'tab3'
    @scenario = Scenario.find_by(id: params[:id])
    @content_configuration = @scenario.content_configuration
  end

  def update_process_settings
    @scenario = Scenario.find_by(id: params[:id])
    @content_configuration = @scenario.content_configuration
    @content_configuration.assign_attributes(process_settings_params)

    @success = @content_configuration.valid?

    if @success
      @content_configuration.save
      flash["success"] = 'Process settings was successfully updated.'
    else
      flash["danger"] = 'Process settings update failed!'
    end
    render layout: false
  end

  def assessment_settings
    @active_tag = 'tab2'
    @scenario = Scenario.find_by(id: params[:id])
    @content_configuration = @scenario.content_configuration
  end

  def update_assessment_settings
    @scenario = Scenario.find_by(id: params[:id])
    @content_configuration = @scenario.content_configuration
    @content_configuration.set_assessment_policy(params[:selected_policy])
    @content_configuration.assign_attributes(assessment_settings_params)

    @success = @content_configuration.valid?

    if @success
      @content_configuration.save
      flash["success"] = 'scenario assessment settings was successfully updated.'
    else
      flash["danger"] = 'scenario assessment settings update failed!'
    end
    render layout: false
  end

  def score_overrides
    @active_tag = 'tab6'
    @scenario = Scenario.find_by(id: params[:id])
    @content_configuration = @scenario.content_configuration

    @score_overrides = @content_configuration.score_overrides

    render layout: false
  end

  def files
    @active_tag = 'tab9'

    @sort_model = ProjectFile.new
    @scenario = Scenario.lookup_by_id(params[:id])
    @project_files = @scenario.project_files.order(get_sort(@sort_model)).page(params[:page])

    render layout: false
  end

  def reports
    @active_tag = 'tab7'

    @sort_model = Report.new

    @scenario = Scenario.lookup_by_id(params[:id])
    filter = SearchFilter::ReportIndexFilterV1.new(nil, nil, nil,nil,[@scenario.id])
    @scenario_reports = Report.index_load(filter, get_sort(nil), params[:page], current_user)

    render layout: false
  end

  def analytics
    @active_tag = 'tab11'

    @scenario = Scenario.lookup_by_id(params[:id])

    if params[:analysis_group_id].nil?
      @analysis_group_id = current_user.preference(self.class.name, 'analytics', UserPreference.analysis_group, @scenario.id)
      @analysis_group_id = '' unless AnalysisGroup.available(@analysis_group_id)
    else
      @analysis_group_id = params[:analysis_group_id]
      current_user.set_preference(self.class.name, 'analytics', UserPreference.analysis_group, @scenario.id, @analysis_group_id, nil)
    end

    if params[:name_filter].nil?
      @name_filter = current_user.preference(self.class.name, 'analytics', UserPreference.name_filter, @scenario.id)
    else
      @name_filter = params[:name_filter]
      current_user.set_preference(self.class.name, 'analytics', UserPreference.name_filter, @scenario.id, @name_filter, nil)
    end

    AnalyticData.load_data_by_scenario(@scenario)

    @sort_model = AnalyticData.new

    @project_analytics = (!AnalysisGroup.valid?(@analysis_group_id) ? AnalyticData.where(@name_filter.blank? ? '1 = ? ' : 'lower(name) like ? ', @name_filter.blank? ? 1 : '%' + @name_filter.downcase + '%') :
                              AnalyticData.joins('left join analysis_groups_variables on analysis_groups_variables.variable_id = analytic_data.variable_id')
                                  .joins('left join analysis_groups_scores on analysis_groups_scores.analysis_score_id = analytic_data.analysis_score_id')
                                  .where('(analysis_groups_variables.analysis_group_id = ? or analysis_groups_scores.analysis_group_id = ?) and ' + (@name_filter.blank? ? '1 = ? ' : 'lower(name) like ? '), @analysis_group_id, @analysis_group_id, @name_filter.blank? ? 1 : '%' + @name_filter.downcase + '%'))
                             .page(params[:page])
  end

  def tasks
    @active_tag = 'tab10'
    @sort_model = WorkflowTask.new

    @scenario = Scenario.lookup_by_id(params[:id])
    @tasks = ProjectWorkflow.task_load(@scenario, get_sort(@sort_model), params[:page])

    @detail_path = perform_model_workflow_task_path('%id%', Scenario.name, @scenario.id)

    render layout: false
  end

  def select_workflow_dialog
    @form_action = 'start_workflow_dialog'
    @scenario = Scenario.lookup_by_id(params[:id])

    render layout: false
  end

  def start_workflow_dialog
    @form_action = 'start_workflow_dialog'
    @scenario = Scenario.lookup_by_id(params[:id])
    @success = true

    if !nil_or_empty(params[:workflow_id])
      @scenario.start_workflow(params[:workflow_id])
      flash['success'] = 'Scenario workflow was started.'
    else
      @success = false
      @scenario.errors.add(:workflow_id, 'is required')
      flash['danger'] = 'Form contains errors!'
    end
  end

  def destroy
    @scenario = Scenario.lookup_by_id(params[:id])

    respond_to do |format|
      if @scenario.delete(current_user)
        flash["success"] = "'#{@scenario.name}' and its assessments were successfully deleted."
        format.js {}
        format.json {render json: @scenario, status: :ok, location: @scenario}
      end
    end
  end

  def create_scenario_object(course_id)
    content_configuration = ContentConfiguration.new(properties_content_configuration_params)
    content_configuration.id = SecureRandom.uuid
    scenario = Scenario.new(scenario_params)
    scenario.course_id = course_id
    scenario.start_date = Utils.string_to_date(params[:start_date], '%m-%d-%Y').noon unless nil_or_blank params[:start_date]
    scenario.end_date = Utils.string_to_date(params[:end_date], '%m-%d-%Y').midnight unless nil_or_blank params[:end_date]
    scenario.tag_ids = params[:tag_ids]
    scenario.content_configuration_id = content_configuration.id
    [scenario, content_configuration]
  end

  def create
    @form_action = 'create'

    @scenario = Scenario.new
    @resource_select_options = Resource.account_for_select(@scenario.account_id)
    @created_scenarios = []
    @all_created = false
    course_ids = params[:course_ids]
    course_ids = course_ids.reject {|el| nil_or_blank el} unless course_ids.nil?

    if course_ids.blank?
      @scenario, @content_configuration = create_scenario_object(nil)
      Scenario.validate_content_configuration_properties(@content_configuration)
      @scenario.valid?
    else
      course_ids.each do |id|
        unless nil_or_blank id
          @scenario, @content_configuration = create_scenario_object(id)

          Scenario.validate_content_configuration_properties(@content_configuration)
          if @scenario.valid? && !@content_configuration.errors.any?
            @content_configuration.save
            @scenario.inherit_assessment_settings_from_course
            @scenario.inherit_process_settings_from_course
            @scenario.inherit_users_from_course
            if @scenario.save
              @created_scenarios.push(@scenario)
              @scenario.announce if @scenario.status.is_in_progress_status
              @course = Course.lookup_by_id(id)
            end
          end
        end
      end
      Scenario.update_aging_scenarios
      @all_created = course_ids.size == @created_scenarios&.size
    end

    respond_to do |format|
      if @all_created
        flash['success'] = 'Scenario was successfully created.'
        format.js {}
        format.json {render json: @scenario, status: :created, location: @scenario}
      else
        format.js {}
        flash["warning"] = 'Please correct the errors below and try again.'

        format.json {render json: @scenario.errors, status: :unprocessable_entity}
      end
    end
  end

  def user_settings
    @active_tag = 'tab8'
    @scenario = Scenario.find_by(id: params[:id])

    render layout: false
  end

  def user_settings_update
    @active_tag = 'tab8'
    @scenario = Scenario.find_by(id: params[:id])

    @scenario.update({:owner_user_id => params[:owner_user_id]})
  end

  # API to return scenarios list for a course
  def course_scenarios
    course = Course.find_by(id: params[:course_id], suspended: false)
    scenarios  = course.nil? ? Scenario.none : Scenario.where(course_id: course.id, suspended: false, is_personal_use: false).select(:id, :name)
    render html: view_context.options_from_collection_for_select(scenarios, :id, :name, 1)
  end

  def suspend
    @scenario = Scenario.find_by(id: params[:id])
    @scenario.suspended ?
        @scenario.unsuspend :
        @scenario.suspend
  end

  def bulk_apply_dialog
    @bulk_apply = Scenario.new
    render layout: false
  end

  def bulk_apply_reload
    @bulk_apply = Scenario.new
  end

  def bulk_apply_save
    default_search = SearchFilter.default_scenario_index_filter
    search_result = SearchFilter.resolve(current_user, self.class.name, 'index', params, default_search)
    @bulk_apply = Scenario.new

    ScenarioBulkApply.validate(@bulk_apply, params)
    @success = @bulk_apply.errors.size == 0

    if @success
      ScenarioBulkApply.schedule(search_result.filter, params, current_user.id)
      flash["success"] = 'Bulk Apply was scheduled.  You will receive an email when it is done.'
    else
      flash["warning"] = 'Please correct the errors below and try again.'
    end
  end

  def status
    scenario = Scenario.new
    if nil_or_blank(params[:start_date])
      return render html: ''
    end
    scenario.start_date = Date.strptime(params[:start_date], '%m-%d-%Y')
    unless nil_or_blank(params[:end_date])
      scenario.end_date = Date.strptime(params[:end_date], '%m-%d-%Y')
    end
    render html: scenario.status&.name
  end


  def add_users_dialog
    @scenario = Scenario.find_by(id: params[:id])
    if @scenario.is_personal_use
      @available_roles = Role.where(role_code: Role.account_user_role)
    else
      @available_roles = Role.where(role_code: Role.lower_than_course_admin)
    end
    render layout: false
  end

  def add_users
    @scenario = add_user_to_model(Scenario, params)
  end

  def account_users_by_role
    @scenario = Scenario.find_by(id: params[:id])
    role = Role.find_by(id: params[:role_id])
    @users = @scenario.course.users_by_role(role.role_code).where("users.id NOT IN (?)", @scenario.users_by_role(role.role_code).select(:id))
    render html: view_context.options_from_collection_for_select(@users, :id, :name, 1)
  end


  def edit_user_dialog
    @scenario, @user, @user_roles, @available_roles = edit_user_in_model_dialog(Scenario, params, Role.lower_than_course_admin, :course)
    if @scenario.is_personal_use
      @available_roles = @scenario.course.user_roles(@user.id).where(role_code: Role.account_user_role)
    end
    render layout: false
  end

  def save_user
    @scenario = save_user_in_model(Scenario, params)
  end

  def remove_user
    remove_user_from_model(Scenario, params)
  end


  def release_results
    @scenario = Scenario.find_by(id:params[:id])
    @scenario.release_results
    @content_configuration = @scenario.content_configuration

    flash['success'] = 'Results were released and users emailed.'
    render 'scenario/form_reload'
  end


  private
  def scenario_params
    params.require(:scenario).permit(:name,
                                     :display_name,
                                     :scenario_type_id,
                                     :description,
                                     :prompt,
                                     :start_date,
                                     :end_date,
                                     :account_id,
                                     :course_id,
                                     :owner_user_id,
                                     :organization_id,
                                     :analysis_benchmark_id,
                                     :status,
                                     :analytics_enabled,
                                     :reporting_threshold,
                                     :scenario_conclusion,
                                     :scenario_teaser,
                                     :interaction_type)

  end

  def properties_content_configuration_params
    params.require(:content_configuration).permit(:communication_type_id,
                                                  :use_client_app,
                                                  :score_source,
                                                  :hold_results)
  end

  def assessment_settings_params
    params.require(:content_configuration).permit(:limit_period,
                                                  :assessment_limit)
  end

  def process_settings_params
    params.require(:content_configuration).permit(:overall_analysis_score_id,
                                                  :assessment_workflow_id,
                                                  :panel_survey_id,
                                                  :panel_survey_instructions,
                                                  :transcription_vendor_id,
                                                  :apptek_model,
                                                  :scenario_report_template_id,
                                                  :transcription_remediation_required)
  end

end
