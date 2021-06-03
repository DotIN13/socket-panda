desc 'Update systemd service'
namespace :panda do
  task :service do
    on roles(:websocket) do |host|
      execute :sudo, :ln, '-s', "#{release_path}/socket-panda.service", '/etc/systemd/system/socket-panda.service'
      info "Host #{host}: Symlinked service file"
    end
  end
end
