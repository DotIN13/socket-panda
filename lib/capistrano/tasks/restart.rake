desc 'Restart socket panda'
namespace :panda do
  task :restart do
    on roles(:websocket) do |host|
      execute :sudo, :systemctl, :restart, 'socket-panda'
      info "Socket panda on host #{host} restarted"
    end
  end
end
