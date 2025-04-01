# cronjob-to-cronicle-migration
This script converts server cronjobs using crond service will automatically migrated to cronicle service



##########run script in server 
bash cronjob-to-cronicle-migration.sh

cat cronjob -l >> crons.txt

######here we get category id using this cli command

    curl -X GET "http://xxxxxxxxxxxx:3012/api/app/get_schedule" \
    -H "x-api-key: xxxxxxxxxxxxxxxxxxxxxxxxxxx" \
    -u "user:password"

    example:-  "category":"cm8mvxag301"

#########create event################

curl -X POST "http://xxxxxxxxxxxx:3012/api/app/create_event" \
    -H "Content-Type: application/json" \
    -H "x-api-key: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" \
    -u "username:password" \
    -d '{
      "title": "Testmail Job",
      "category": "xxxxxxxxxxx",
      "plugin": "shellplug",
      "target": "maingrp",
      "timing": { "minut es": [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55] },
      "enabled": 1,
      "params": {
        "script": "echo Hello Cronicle > /tmp/test.txt"
      },
      "notify_fail": "sro0618346@gmail.com"
    }'


########delete events#################

for event_id in $(curl -s -X GET "http://xxxxxxxxxxxxxxxx:3012/api/app/get_schedule" \
     -H "x-api-key: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" \
     -u "user:password" | jq -r '.rows[].id'); do           echo "Deleting event: $event_id";          curl -s -X POST "http://xxxxxxxxxxxxxxxxxxxxxx:3012/api/app/delete_event"          -H "x-api-key: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"          -u "user:password"          -H "Content-Type: application/json"          -d "{\"id\": \"$event_id\"}"; done
