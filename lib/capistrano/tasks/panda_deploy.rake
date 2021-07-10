desc 'Deploy and start service'
namespace :panda do
  task :deploy do
    on roles(:websocket) do |host|
      invoke :deploy
      invoke 'panda:restart'
      info "Host #{host} deployed"
    end
  end
end
