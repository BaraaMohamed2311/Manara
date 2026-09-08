provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "source"
  region = "us-east-1"
}

provider "aws" {
  alias  = "destination"
  region = "us-west-2" 
}