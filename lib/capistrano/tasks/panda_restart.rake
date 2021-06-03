namespace :panda do
  %i[start stop restart].each do |action|
    desc "#{action.capitalize} socket panda"
    task action do
      on roles(:websocket) do |host|
        # execute 'sudo /usr/bin/systemctl start socket-panda.service'
        execute :sudo, '/usr/bin/systemctl', action, 'socket-panda.service'
        info "Completed action #{action} on host #{host}"
      end
    end
  end
end
