#!/bin/bash

# Ubuntu server ssl from letsencrypt install script

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root for security reasons."
        print_status "Please run as a regular user with sudo privileges."
        exit 1
    fi
}

# Function to check if domain is accessible
check_domain() {
    local domain=$1
    print_status "Checking if domain $domain is accessible..."
    
    if curl -s --head --request GET "http://$domain" | grep "200 OK" > /dev/null; then
        print_success "Domain $domain is accessible"
        return 0
    else
        print_warning "Domain $domain may not be properly configured or accessible"
        read -p "Do you want to continue anyway? (y/N): " continue_anyway
        if [[ $continue_anyway != "y" && $continue_anyway != "Y" ]]; then
            print_error "Exiting. Please ensure your domain is properly configured."
            exit 1
        fi
    fi
}

# Function to detect web server
detect_webserver() {
    if systemctl is-active --quiet apache2; then
        echo "apache"
    elif systemctl is-active --quiet nginx; then
        echo "nginx"
    else
        echo "unknown"
    fi
}

# Function to install certbot
install_certbot() {
    print_status "Installing Certbot..."
    
    # Update package list
    sudo apt update
    
    # Install snapd if not already installed
    if ! command -v snap &> /dev/null; then
        print_status "Installing snapd..."
        sudo apt install -y snapd
        sudo systemctl enable --now snapd.socket
        sudo ln -sf /var/lib/snapd/snap /snap
    fi
    
    # Install certbot via snap
    print_status "Installing Certbot via snap..."
    sudo snap install core; sudo snap refresh core
    sudo snap install --classic certbot
    
    # Create symlink
    sudo ln -sf /snap/bin/certbot /usr/bin/certbot
    
    print_success "Certbot installed successfully"
}

# Function to install SSL certificate
install_ssl_certificate() {
    local domain=$1
    local email=$2
    local webserver=$3
    
    print_status "Installing SSL certificate for $domain..."
    
    case $webserver in
        "apache")
            print_status "Detected Apache web server"
            sudo certbot --apache -d "$domain" --email "$email" --agree-tos --non-interactive
            ;;
        "nginx")
            print_status "Detected Nginx web server"
            sudo certbot --nginx -d "$domain" --email "$email" --agree-tos --non-interactive
            ;;
        *)
            print_status "No supported web server detected. Using standalone mode."
            print_warning "This will temporarily stop your web server."
            read -p "Continue? (y/N): " continue_standalone
            if [[ $continue_standalone == "y" || $continue_standalone == "Y" ]]; then
                sudo certbot certonly --standalone -d "$domain" --email "$email" --agree-tos --non-interactive
            else
                print_error "SSL installation cancelled."
                exit 1
            fi
            ;;
    esac
}

# Function to setup auto-renewal
setup_auto_renewal() {
    print_status "Setting up automatic certificate renewal..."
    
    # Test renewal
    sudo certbot renew --dry-run
    
    if [[ $? -eq 0 ]]; then
        print_success "Auto-renewal test successful"
        print_status "Certificates will automatically renew via systemd timer"
    else
        print_error "Auto-renewal test failed"
        exit 1
    fi
}

# Function to display certificate info
show_certificate_info() {
    local domain=$1
    print_status "Certificate information for $domain:"
    sudo certbot certificates -d "$domain"
}

# Function to configure firewall
configure_firewall() {
    print_status "Configuring firewall for HTTPS..."
    
    if command -v ufw &> /dev/null; then
        print_status "Configuring UFW firewall..."
        sudo ufw allow 'Nginx Full' 2>/dev/null || sudo ufw allow 'Apache Full' 2>/dev/null || {
            sudo ufw allow 80/tcp
            sudo ufw allow 443/tcp
        }
        print_success "Firewall configured for HTTP and HTTPS"
    else
        print_warning "UFW not found. Please ensure ports 80 and 443 are open."
    fi
}

# Main function
main() {
    clear
    echo "=================================================="
    echo "   SSL Certificate Installation Script"
    echo "   for Ubuntu Server with Let's Encrypt"
    echo "=================================================="
    echo
    
    # Check if running as root
    check_root
    
    # Get domain name
    read -p "Enter your domain name (e.g., example.com): " domain
    if [[ -z "$domain" ]]; then
        print_error "Domain name is required"
        exit 1
    fi
    
    # Get email address
    read -p "Enter your email address for Let's Encrypt notifications: " email
    if [[ -z "$email" ]]; then
        print_error "Email address is required"
        exit 1
    fi
    
    # Check domain accessibility
    check_domain "$domain"
    
    # Detect web server
    webserver=$(detect_webserver)
    print_status "Detected web server: $webserver"
    
    # Install certbot if not already installed
    if ! command -v certbot &> /dev/null; then
        install_certbot
    else
        print_success "Certbot is already installed"
    fi
    
    # Configure firewall
    configure_firewall
    
    # Install SSL certificate
    install_ssl_certificate "$domain" "$email" "$webserver"
    
    # Setup auto-renewal
    setup_auto_renewal
    
    # Show certificate info
    show_certificate_info "$domain"
    
    print_success "SSL certificate installation completed successfully!"
    print_status "Your website should now be accessible via HTTPS: https://$domain"
    
    echo
    echo "=================================================="
    echo "   Installation Complete!"
    echo "=================================================="
    echo "• Certificate installed for: $domain"
    echo "• Auto-renewal configured"
    echo "• Certificate expires in 90 days"
    echo "• Renewal will happen automatically"
    echo "=================================================="
}

# Run the main function
main "$@"