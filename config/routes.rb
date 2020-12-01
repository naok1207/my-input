Rails.application.routes.draw do
  resources :qiitum, only: %i[ index ]

  namespace :api do
    resources :qiitum, only: [] do
      post 'callback', to: 'qiitum#callback', on: :collection
    end
    resources :graduation_research, only: [] do
      post 'callback', to: 'graduation_research#callback', on: :collection
    end
  end
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
