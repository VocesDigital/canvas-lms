#
# Copyright (C) 2011 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

require File.expand_path(File.dirname(__FILE__) + '/../api_spec_helper')

describe UsersController, :type => :integration do
  before do
    course_with_teacher(:active_all => true, :user => user_with_pseudonym(:active_all => true))
    @teacher_course = @course
    @student_course = course(:active_all => true)
    @student_course.enroll_student(@user).accept!
    # an assignment i need to submit (needs_submitting)
    @a = Assignment.create!(:context => @student_course, :due_at => 6.days.from_now, :title => 'required work', :submission_types => 'online_text_entry', :points_possible => 10)

    # an assignment i created, and a student who submits the assignment (needs_grading)
    @a2 = Assignment.create!(:context => @teacher_course, :due_at => 1.day.from_now, :title => 'text', :submission_types => 'online_text_entry', :points_possible => 15)
    @me = @user
    student = user(:active_all => true)
    @user = @me
    @teacher_course.enroll_student(student).accept!
    @sub = @a2.reload.submit_homework(student, :submission_type => 'online_text_entry', :body => 'done')
    @a1_json = 
      {
        'type' => 'submitting',
        'assignment' => {
          'name' => 'required work',
          'description' => nil,
          'id' => @a.id,
          'course_id' => @student_course.id,
          'muted' => false,
          'points_possible' => 10,
          'submission_types' => ['online_text_entry'],
          'due_at' => @a.due_at.as_json,
          'html_url' => course_assignment_url(@a.context_id, @a),
        },
        'ignore' => api_v1_users_todo_ignore_url(@a.asset_string, 'submitting', :permanent => 0),
        'ignore_permanently' => api_v1_users_todo_ignore_url(@a.asset_string, 'submitting', :permanent => 1),
        'html_url' => "#{course_assignment_url(@a.context_id, @a.id)}#submit",
        'context_type' => 'Course',
        'course_id' => @student_course.id,
      }
    @a2_json =
      {
        'type' => 'grading',
        'assignment' => {
          'name' => 'text',
          'description' => nil,
          'id' => @a2.id,
          'course_id' => @teacher_course.id,
          'muted' => false,
          'points_possible' => 15,
          'needs_grading_count' => 1,
          'submission_types' => ['online_text_entry'],
          'due_at' => @a2.due_at.as_json,
          'html_url' => course_assignment_url(@a2.context_id, @a2),
        },
        'needs_grading_count' => 1,
        'ignore' => api_v1_users_todo_ignore_url(@a2.asset_string, 'grading', :permanent => 0),
        'ignore_permanently' => api_v1_users_todo_ignore_url(@a2.asset_string, 'grading', :permanent => 1),
        'html_url' => speed_grader_course_gradebook_url(@a2.context_id, :assignment_id => @a2.id),
        'context_type' => 'Course',
        'course_id' => @teacher_course.id,
      }
  end

  def another_submission
    @me = @user
    student2 = user(:active_all => true)
    @user = @me
    @teacher_course.enroll_student(student2).accept!
    @sub2 = @a2.reload.submit_homework(student2, :submission_type => 'online_text_entry', :body => 'me too')
  end

  it "should check for auth" do
    get("/api/v1/users/self/todo")
    response.status.should == '401 Unauthorized'
    JSON.parse(response.body).should == {"message"=>"Invalid access token.", "status"=>"unauthorized"}

    @course = factory_with_protected_attributes(Course, course_valid_attributes)
    raw_api_call(:get, "/api/v1/courses/#{@course.id}/todo",
                :controller => "courses", :action => "todo_items", :format => "json", :course_id => @course.to_param)
    response.status.should == '401 Unauthorized'
    JSON.parse(response.body).should == { 'status' => 'unauthorized', 'message' => 'You are not authorized to perform that action.' }
  end

  it "should return a global user todo list" do
    json = api_call(:get, "/api/v1/users/self/todo",
                    :controller => "users", :action => "todo_items", :format => "json")
    json.sort_by { |t| t['assignment']['id'] }.should == [@a1_json, @a2_json]
  end

  it "should return a course-specific todo list" do
    json = api_call(:get, "/api/v1/courses/#{@student_course.id}/todo",
                    :controller => "courses", :action => "todo_items", :format => "json", :course_id => @student_course.to_param)
    json.should == [@a1_json]

    json = api_call(:get, "/api/v1/courses/#{@teacher_course.id}/todo",
                    :controller => "courses", :action => "todo_items", :format => "json", :course_id => @teacher_course.to_param)
    json.should == [@a2_json]
  end

  it "should ignore a todo item permanently" do
    api_call(:delete, @a2_json['ignore_permanently'],
             :controller => "users", :action => "ignore_item", :format => "json", :purpose => "grading", :asset_string => "assignment_#{@a2.id}", :permanent => "1")
    response.should be_success

    json = api_call(:get, "/api/v1/courses/#{@teacher_course.id}/todo",
                    :controller => "courses", :action => "todo_items", :format => "json", :course_id => @teacher_course.to_param)
    json.should == []

    # after new student submission, still ignored
    another_submission
    json = api_call(:get, "/api/v1/courses/#{@teacher_course.id}/todo",
                    :controller => "courses", :action => "todo_items", :format => "json", :course_id => @teacher_course.to_param)
    json.should == []
  end

  it "should ignore a todo item until the next change" do
    api_call(:delete, @a2_json['ignore'],
             :controller => "users", :action => "ignore_item", :format => "json", :purpose => "grading", :asset_string => "assignment_#{@a2.id}", :permanent => "0")
    response.should be_success

    json = api_call(:get, "/api/v1/courses/#{@teacher_course.id}/todo",
                    :controller => "courses", :action => "todo_items", :format => "json", :course_id => @teacher_course.to_param)
    json.should == []

    # after new student submission, no longer ignored
    another_submission
    json = api_call(:get, "/api/v1/courses/#{@teacher_course.id}/todo",
                    :controller => "courses", :action => "todo_items", :format => "json", :course_id => @teacher_course.to_param)
    @a2_json['needs_grading_count'] = 2
    @a2_json['assignment']['needs_grading_count'] = 2
    json.should == [@a2_json]
  end
end
