YOUTUBE PARSE SYSTEM

DEVELOPMENT

To install mssql tiny_tds in mac use
gem install tiny_tds -- --with-freetds-include=/opt/homebrew/include --with-freetds-lib=/opt/homebrew/lib
sudo apt-get install freetds-dev UBUNTU

To start docker file execute:
docker-compose --env-file dev.env -f docker-compose.dev.yml up
