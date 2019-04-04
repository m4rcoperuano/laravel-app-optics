## Setup Instructions

This small repo is so you can setup Laravel using Docker. I suggest not cloning this repo, just downloading it and using it as a starter directory for your new Laravel instance. 

1. So obvious pre-requisite - install Docker.
2. Copy the `.env.example` file and rename it to `.env`.
3. (Optional) If your port 8000 is in use, or your port 3307 is in use, make sure to update those port forwarding
inside the `docker-compose.yml` file. Look for the following sections in that file:
    * db -> ports -> 3307:3306
        * Change 3307 to your desired port. This is how you will access the docker database using your host machine.
    * web -> ports -> 8000:80
        * Change the 8000 to your desired port. This is how you will access the docker site in your host machine (navigating to localhost:YOUR_PORT_NUMBER).
4. When you're ready, navigate to this folder using terminal, and run `docker-compose up`. 
5. After your environment is running, you may need to go into your docker container for the app and run composer install. If so, just run the command: `docker-compose exec app bash`, and run `composer install`.
6. And! You may need to create a laravel app key. So inside the docker container, run `php artisan key:generate`.

That should be it!