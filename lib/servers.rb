role :new_dbs,
        "new_db_hostname"

role :test_dba,
	"testdba01",
	"testdba01"

role :my_example_role,
	"my_example_server",
	"my_other_example_server"
 	{
		:user => 'my_example_user_id',
		:ssh_options =>
		{
        		:keys => '/my_example_location/my_example_key',
			:forward_agent => 'true',
		}
	}
