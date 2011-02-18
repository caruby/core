package clinicaltrials.domain;

public class Address extends DomainObject
{
	/**
	 * The Street address.
	 */
	private String street;

	/**
	 * The Street city.
	 */
	private String city;

	/**
	 * The Street state.
	 */
	private String state;

	/**
	 * The Street country
	 */
	private String country;

	/**
	 * The Street zip code.
	 */
	private String zipCode;
	
	public Address()
	{
	}

	/**
	 * @return the street of the address
	 */
	public String getStreet()
	{
		return street;
	}

	/**
	 * @param street
	 * Sets the street of the address
	 */
	public void setStreet(String street)
	{
		this.street = street;
	}

	/**
	 * @return city of the address.
	 */
	public String getCity()
	{
		return city;
	}

	/**
	 * @param the city of the address
	 */
	public void setCity(String city)
	{
		this.city = city;
	}

	/**
	 * @return state of the address
	 */
	public String getState()
	{
		return state;
	}

	/**
	 * @param state of the address
	 */
	public void setState(String state)
	{
		this.state = state;
	}

	/**
	 * @return country of the address
	 */
	public String getCountry()
	{
		return country;
	}

	/**
	 * @param country of the address
	 */
	public void setCountry(String country)
	{
		this.country = country;
	}

	/**
	 * @return zipCode of the address
	 */
	public String getZipCode()
	{
		return zipCode;
	}

	/**
	 * @param the zipCode of the address
	 */
	public void setZipCode(String zipCode)
	{
		this.zipCode = zipCode;
	}
}