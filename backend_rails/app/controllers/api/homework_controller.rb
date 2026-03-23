# frozen_string_literal: true

module Api
  class HomeworkController < ApplicationController
    include Authenticatable

    # GET /api/my/homework — homework items for current client
    def index
      client = current_user.client_profile
      unless client
        render json: { error: "Client profile not found" }, status: :not_found
        return
      end

      items = HomeworkItem
        .where(client_id: client.id)
        .order(created_at: :asc)
        .map { |h| homework_item_json(h) }

      render json: items
    end

    # PATCH /api/homework/:id — mark homework as completed
    def update
      client = current_user.client_profile
      unless client
        render json: { error: "Client profile not found" }, status: :not_found
        return
      end

      item = HomeworkItem.find_by(id: params[:id], client_id: client.id)
      unless item
        render json: { error: "Homework item not found" }, status: :not_found
        return
      end

      if params[:completed]
        item.update!(completed: true, completed_at: Time.current)
      end

      render json: homework_item_json(item)
    end

    private

    def homework_item_json(item)
      {
        id: item.id,
        description: item.description,
        completed: item.completed,
        completed_at: item.completed_at&.iso8601
      }
    end
  end
end
